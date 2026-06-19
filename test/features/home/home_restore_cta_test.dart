import 'package:decimal/decimal.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUserCredential extends Mock implements UserCredential {}

/// Empty-group dashboard overrides (mirrors home_screen_groups_test.dart) so
/// the restore CTA renders in the empty state.
List<Override> _emptyOverrides() => [
  userGroupsProvider.overrideWith((ref) => Stream.value([])),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (
        byCurrency: <CurrencyBalance>[],
        groupCount: 0,
        isLoading: false,
      ),
      partial: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => const AsyncValue.data((
      balances: <String, List<UserBalance>>{},
      totalSpent: <String, Decimal>{},
      eventCount: 0,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{},
      memberRawNames: <String, String>{},
    )),
  ),
  groupEventsProvider.overrideWith((ref, groupId) => Stream.value([])),
  currentUserIdProvider.overrideWithValue('test-user-id'),
];

Widget _buildApp({
  required SharedPreferences prefs,
  required AuthRecoveryService recovery,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
      GoRoute(
        path: '/create-group',
        builder: (ctx, state) =>
            const Scaffold(body: Text('CreateGroupScreen')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (ctx, state) => const Scaffold(body: Text('JoinGroupScreen')),
      ),
      // The Google CTA must NOT navigate here (PR3); the email-fallback CTA
      // MUST (#441 PR4).
      GoRoute(
        path: '/recover',
        builder: (ctx, state) => const Scaffold(body: Text('RecoverScreenStub')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      linkedEmailProvider.overrideWithValue('secured@example.com'),
      authRecoveryServiceProvider.overrideWithValue(recovery),
      ..._emptyOverrides(),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  late SharedPreferences prefs;
  late _MockAuthRecoveryService recovery;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    recovery = _MockAuthRecoveryService();
  });

  testWidgets('empty-state restore CTA triggers the Google restore swap, '
      'not a /recover route push', (tester) async {
    when(
      () => recovery.restoreWithGoogle(),
    ).thenAnswer((_) async => _MockUserCredential());

    await tester.pumpWidget(_buildApp(prefs: prefs, recovery: recovery));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home_empty_recover_cta')));
    await tester.pump();

    verify(() => recovery.restoreWithGoogle()).called(1);
    // It is an auth action now, not navigation — the old /recover screen must
    // never appear.
    expect(find.text('RecoverScreenStub'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('a cancelled Google sheet is silent (no error snackbar)', (
    tester,
  ) async {
    when(() => recovery.restoreWithGoogle()).thenThrow(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );

    await tester.pumpWidget(_buildApp(prefs: prefs, recovery: recovery));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home_empty_recover_cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text("Couldn't sign in with Google. Please try again."),
      findsNothing,
    );

    await tester.pumpAndSettle();
  });

  testWidgets('empty-state email-fallback CTA pushes /recover and does NOT '
      'trigger the Google swap (#441 PR4)', (tester) async {
    // Tall surface: the email CTA sits below the Google CTA and lands under
    // the fold at the default 800x600 test viewport.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildApp(prefs: prefs, recovery: recovery));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('home_empty_recover_email_cta')),
    );
    await tester.tap(find.byKey(const Key('home_empty_recover_email_cta')));
    await tester.pumpAndSettle();

    expect(find.text('RecoverScreenStub'), findsOneWidget);
    verifyNever(() => recovery.restoreWithGoogle());
  });

  testWidgets('a real restore error surfaces a snackbar', (tester) async {
    when(
      () => recovery.restoreWithGoogle(),
    ).thenThrow(StateError('GOOGLE_SERVER_CLIENT_ID missing'));

    await tester.pumpWidget(_buildApp(prefs: prefs, recovery: recovery));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home_empty_recover_cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text("Couldn't sign in with Google. Please try again."),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
  });
}
