import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/screens/recover_pending_screen.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

// Backing StateProvider so individual tests can flip the simulated uid
// without rebuilding the ProviderScope (the screen reads uidProvider in
// initState; ref.listen then fires when it changes).
final _testUidProvider = StateProvider<String?>((_) => 'anon-1');

// NoTransitionPage skips MaterialPage's transition so the AbsorbPointer
// overlay clears immediately — otherwise taps within the same pump frame
// land on the route barrier instead of the screen.
GoRouter _buildRouter({
  String initial = '/recover/pending?email=a%40b.com',
  bool nestedRecover = true,
}) {
  return GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/home',
        pageBuilder: (_, _) => const NoTransitionPage(
          child: Scaffold(body: Text('HOME')),
        ),
      ),
      if (nestedRecover)
        GoRoute(
          path: '/recover',
          pageBuilder: (_, _) => const NoTransitionPage(
            child: Scaffold(body: Text('RECOVER')),
          ),
          routes: [
            GoRoute(
              path: 'pending',
              pageBuilder: (_, state) => NoTransitionPage(
                child: RecoverPendingScreen(
                  email: state.uri.queryParameters['email'] ?? '',
                ),
              ),
            ),
          ],
        )
      else
        GoRoute(
          path: '/recover/pending',
          pageBuilder: (_, state) => NoTransitionPage(
            child: RecoverPendingScreen(
              email: state.uri.queryParameters['email'] ?? '',
            ),
          ),
        ),
    ],
  );
}

Widget _buildWidget({
  required _MockRecoveryService service,
  String initialUid = 'anon-1',
  String? pendingLink,
  String initial = '/recover/pending?email=a%40b.com',
  bool nestedRecover = true,
}) {
  return ProviderScope(
    overrides: [
      authRecoveryServiceProvider.overrideWithValue(service),
      _testUidProvider.overrideWith((_) => initialUid),
      uidProvider.overrideWith((ref) => ref.watch(_testUidProvider)),
      if (pendingLink != null)
        pendingEmailLinkProvider.overrideWith((_) => pendingLink),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _buildRouter(
        initial: initial,
        nestedRecover: nestedRecover,
      ),
    ),
  );
}

void main() {
  late _MockRecoveryService service;

  setUp(() {
    service = _MockRecoveryService();
  });

  testWidgets('renders email, cooldown text, and disabled resend', (tester) async {
    await tester.pumpWidget(_buildWidget(service: service));
    await tester.pump();

    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.textContaining('a@b.com'), findsOneWidget);
    expect(find.textContaining('Resend in'), findsOneWidget);
    expect(
      find.textContaining("Can't find it? Check your spam folder."),
      findsOneWidget,
    );

    final resend = tester.widget<OutlinedButton>(
      find.byKey(const Key('recoverPending.resend')),
    );
    expect(resend.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows pending-link banner when bootstrap captured a link', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildWidget(
        service: service,
        pendingLink: 'https://example.com/?oobCode=abc',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('recoverPending.linkSeen')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancel pops when stack is non-empty', (tester) async {
    await tester.pumpWidget(_buildWidget(service: service));
    await tester.pump();

    await tester.tap(find.byKey(const Key('recoverPending.cancel')));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('RECOVER'), findsOneWidget);
  });

  testWidgets('cancel falls back to /home when no parent on stack', (tester) async {
    await tester.pumpWidget(
      _buildWidget(service: service, nestedRecover: false),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('recoverPending.cancel')));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('close icon button uses the same cancel path', (tester) async {
    await tester.pumpWidget(_buildWidget(service: service));
    await tester.pump();

    await tester.tap(find.byIcon(Iconsax.close_square));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('RECOVER'), findsOneWidget);
  });

  testWidgets('resend after cooldown calls service and shows success status', (
    tester,
  ) async {
    when(() => service.sendRecoveryLink(any())).thenAnswer((_) async {});

    await tester.pumpWidget(_buildWidget(service: service));
    await tester.pump(const Duration(seconds: 61));

    expect(find.text('Resend link'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recoverPending.resend')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('recoverPending.status')), findsOneWidget);
    verify(() => service.sendRecoveryLink('a@b.com')).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resend surfaces FirebaseAuthException with the error code', (
    tester,
  ) async {
    when(() => service.sendRecoveryLink(any())).thenThrow(
      fa.FirebaseAuthException(code: 'too-many-requests'),
    );

    await tester.pumpWidget(_buildWidget(service: service));
    await tester.pump(const Duration(seconds: 61));

    await tester.tap(find.byKey(const Key('recoverPending.resend')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('recoverPending.error')), findsOneWidget);
    expect(find.textContaining('too-many-requests'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resend with generic Exception shows generic error', (
    tester,
  ) async {
    when(() => service.sendRecoveryLink(any())).thenThrow(Exception('boom'));

    await tester.pumpWidget(_buildWidget(service: service));
    await tester.pump(const Duration(seconds: 61));

    await tester.tap(find.byKey(const Key('recoverPending.resend')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('recoverPending.error')), findsOneWidget);
    expect(find.textContaining("Couldn't resend"), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uid swap to a new user routes home', (tester) async {
    await tester.pumpWidget(_buildWidget(service: service));
    await tester.pump();

    expect(find.text('Check your inbox'), findsOneWidget);

    // Flip the simulated uid — ref.listen on uidProvider fires and the
    // screen navigates home.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container.read(_testUidProvider.notifier).state = 'recovered-2';
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('HOME'), findsOneWidget);
  });
}
