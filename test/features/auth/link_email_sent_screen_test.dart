import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/screens/link_email_sent_screen.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/profile/link-email/sent?email=alice%40example.com',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('PROFILE')),
      ),
      GoRoute(
        path: '/profile/link-email',
        builder: (_, _) => const Scaffold(body: Text('LINK_EMAIL')),
        routes: [
          GoRoute(
            path: 'sent',
            builder: (_, state) => LinkEmailSentScreen(
              email: state.uri.queryParameters['email'] ?? '',
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _wrap(GoRouter router, _MockRecoveryService service) {
  return ProviderScope(
    overrides: [authRecoveryServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
    ),
  );
}

void main() {
  late _MockRecoveryService service;

  setUp(() {
    service = _MockRecoveryService();
  });

  testWidgets('renders the email address and 60s cooldown text', (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pumpAndSettle();

    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.textContaining('alice@example.com'), findsOneWidget);
    expect(find.textContaining('Resend in'), findsOneWidget);
    // Spam-folder helper text
    expect(
      find.textContaining("Can't find it? Check your spam folder."),
      findsOneWidget,
    );
  });

  testWidgets('Resend button is disabled during cooldown', (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pump();

    final resendBtn = tester.widget<OutlinedButton>(
      find.byKey(const Key('linkEmailSent.resend')),
    );
    expect(resendBtn.onPressed, isNull);
  });

  testWidgets('Done navigates back to /profile/link-email parent',
      (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('linkEmailSent.done')));
    await tester.pumpAndSettle();

    // Back from /profile/link-email/sent goes to /profile/link-email.
    expect(find.text('LINK_EMAIL'), findsOneWidget);
  });

  testWidgets('Done falls back to /profile when stack is empty', (tester) async {
    final router = GoRouter(
      initialLocation: '/profile/link-email/sent?email=x%40x.com',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Scaffold(body: Text('PROFILE')),
        ),
        GoRoute(
          path: '/profile/link-email/sent',
          builder: (_, state) => LinkEmailSentScreen(
            email: state.uri.queryParameters['email'] ?? '',
          ),
        ),
      ],
    );
    await tester.pumpWidget(_wrap(router, service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('linkEmailSent.done')));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE'), findsOneWidget);
  });

  testWidgets('resend after cooldown calls service and shows success status',
      (tester) async {
    when(() => service.linkEmailToCurrentUser(any()))
        .thenAnswer((_) async {});

    await tester.pumpWidget(_wrap(_buildRouter(), service));
    // Burn the 60-second cooldown timer.
    await tester.pump(const Duration(seconds: 61));

    expect(find.text('Resend link'), findsOneWidget);

    await tester.tap(find.byKey(const Key('linkEmailSent.resend')));
    await tester.pump();
    await tester.pump(); // allow async setState

    expect(find.byKey(const Key('linkEmailSent.status')), findsOneWidget);
    verify(() => service.linkEmailToCurrentUser('alice@example.com')).called(1);

    // Cancel the new cooldown timer before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resend surfaces FirebaseAuthException with the error code',
      (tester) async {
    when(() => service.linkEmailToCurrentUser(any())).thenThrow(
      FirebaseAuthException(code: 'too-many-requests'),
    );

    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pump(const Duration(seconds: 61));

    await tester.tap(find.byKey(const Key('linkEmailSent.resend')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('linkEmailSent.error')), findsOneWidget);
    expect(find.textContaining('too-many-requests'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resend with generic Exception shows generic error',
      (tester) async {
    when(() => service.linkEmailToCurrentUser(any()))
        .thenThrow(Exception('boom'));

    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pump(const Duration(seconds: 61));

    await tester.tap(find.byKey(const Key('linkEmailSent.resend')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('linkEmailSent.error')), findsOneWidget);
    expect(find.textContaining("Couldn't resend"), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
