import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/draft_navigation_guard.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #1208: the add/edit expense editor registers a DraftNavigationGuard while
// mounted so a runtime deep-link/notification navigation confirms discard
// before silently replacing the stack over a dirty draft. Mirrors the
// pumping pattern in expense_editor_discard_guard_test.dart.
// Spec: docs/plans/2026-07-13-1208-deeplink-dirty-draft-guard.md

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

/// Two-entry stack (`/home` + the pushed editor route) so dispose (navigate
/// away) unregisters for real, following
/// `expense_editor_discard_guard_test.dart`'s pattern. Bounded pumps only —
/// no `pumpAndSettle` (the editor's `OfflineBanner` watches
/// `connectivityProvider`, whose Timer never settles).
Future<GoRouter> _pumpEditorRoute(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/editor',
        builder: (_, _) => const ExpenseEditorBody(
          groupId: _groupId,
          eventId: _eventId,
          mode: ExpenseEditorMode.add,
          currency: 'OMR',
          onSubmit: _noopSubmit,
        ),
      ),
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

void main() {
  group('ExpenseEditorBody draft navigation guard (#1208)', () {
    setUp(DraftNavigationGuard.instance.reset);
    tearDown(DraftNavigationGuard.instance.reset);

    testWidgets('registers a guard while mounted', (tester) async {
      await _pumpEditorRoute(tester);

      expect(DraftNavigationGuard.instance.hasGuards, isTrue);
    });

    testWidgets('pristine editor: mayNavigate resolves true with no dialog', (
      tester,
    ) async {
      await _pumpEditorRoute(tester);

      final allowed = await DraftNavigationGuard.instance.mayNavigate();
      await tester.pump();

      expect(allowed, isTrue);
      expect(find.text('Discard this expense?'), findsNothing);
    });

    testWidgets(
      'dirty editor: mayNavigate shows the discard dialog; Keep editing '
      'refuses navigation and keeps the editor mounted',
      (tester) async {
        await _pumpEditorRoute(tester);
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.pump();

        final navigateFuture = DraftNavigationGuard.instance.mayNavigate();
        await tester.pump();

        expect(find.text('Discard this expense?'), findsOneWidget);

        await tester.tap(find.text('Keep editing'));
        await tester.pump();

        expect(await navigateFuture, isFalse);
        expect(find.byType(ExpenseEditorBody), findsOneWidget);
      },
    );

    testWidgets(
      'dirty editor: confirming the discard dialog allows navigation',
      (tester) async {
        await _pumpEditorRoute(tester);
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.pump();

        final navigateFuture = DraftNavigationGuard.instance.mayNavigate();
        await tester.pump();

        expect(find.text('Discard this expense?'), findsOneWidget);

        await tester.tap(find.text('Discard'));
        await tester.pump();

        expect(await navigateFuture, isTrue);
      },
    );

    testWidgets('unregisters on dispose (navigate away)', (tester) async {
      final router = await _pumpEditorRoute(tester);
      expect(DraftNavigationGuard.instance.hasGuards, isTrue);

      router.go('/home');
      await tester.pump();
      // Default MaterialPage route transition runs ~450-500ms; a single
      // 300ms pump under-drains it and leaves the old page (and its
      // registered guard) still in the tree.
      await tester.pump(const Duration(milliseconds: 700));

      expect(DraftNavigationGuard.instance.hasGuards, isFalse);
    });

    testWidgets(
      'a discard dialog already up (X tap) refuses a concurrent consult and '
      'never stacks a second dialog (Gate r1 adversary [P2])',
      (tester) async {
        await _pumpEditorRoute(tester);
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.pump();

        await tester.tap(find.byTooltip('Close'));
        await tester.pump();

        expect(find.text('Discard this expense?'), findsOneWidget);

        final allowed = await DraftNavigationGuard.instance.mayNavigate();

        expect(allowed, isFalse);
        expect(find.text('Discard this expense?'), findsOneWidget);
      },
    );
  });
}
