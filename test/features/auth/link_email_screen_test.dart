import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/screens/link_email_screen.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _SentScreen extends StatelessWidget {
  const _SentScreen({required this.email});
  final String email;
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('SENT:$email'));
  }
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/profile/link-email',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('PROFILE')),
      ),
      GoRoute(
        path: '/profile/link-email',
        builder: (_, _) => const LinkEmailScreen(),
        routes: [
          GoRoute(
            path: 'sent',
            builder: (_, state) =>
                _SentScreen(email: state.uri.queryParameters['email'] ?? ''),
          ),
        ],
      ),
    ],
  );
}

Widget _wrap(GoRouter router, _MockRecoveryService service) {
  return ProviderScope(
    overrides: [authRecoveryServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
}

Future<void> _typeAndSubmit(
  WidgetTester tester, {
  required String email,
  required String confirm,
}) async {
  await tester.enterText(find.byKey(const Key('linkEmail.email')), email);
  await tester.enterText(find.byKey(const Key('linkEmail.confirm')), confirm);
  await tester.tap(find.byKey(const Key('linkEmail.submit')));
  await tester.pumpAndSettle();
}

void main() {
  late _MockRecoveryService service;

  setUp(() {
    service = _MockRecoveryService();
  });

  testWidgets('rejects empty email with the validator message', (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('linkEmail.submit')));
    await tester.pump();

    expect(find.text('Enter your email.'), findsWidgets);
    verifyNever(() => service.linkEmailToCurrentUser(any()));
  });

  testWidgets('direct entry back button routes to profile', (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.arrow_left_2));
    await tester.pumpAndSettle();

    expect(find.text('PROFILE'), findsOneWidget);
  });

  testWidgets('rejects mismatched confirmation', (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pumpAndSettle();

    await _typeAndSubmit(
      tester,
      email: 'foo@example.com',
      confirm: 'bar@example.com',
    );

    expect(find.text("Emails don't match."), findsOneWidget);
    verifyNever(() => service.linkEmailToCurrentUser(any()));
  });

  testWidgets(
    'happy path calls service with normalized email and routes to sent',
    (tester) async {
      when(
        () => service.linkEmailToCurrentUser(any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(_buildRouter(), service));
      await tester.pumpAndSettle();

      await _typeAndSubmit(
        tester,
        email: '  Foo@Example.COM ',
        confirm: 'foo@example.com',
      );

      verify(() => service.linkEmailToCurrentUser('foo@example.com')).called(1);
      expect(find.text('SENT:foo@example.com'), findsOneWidget);
    },
  );

  testWidgets(
    'credential-already-in-use surfaces the restore-from-other-account message',
    (tester) async {
      when(
        () => service.linkEmailToCurrentUser(any()),
      ).thenThrow(FirebaseAuthException(code: 'credential-already-in-use'));

      await tester.pumpWidget(_wrap(_buildRouter(), service));
      await tester.pumpAndSettle();

      await _typeAndSubmit(
        tester,
        email: 'foo@example.com',
        confirm: 'foo@example.com',
      );

      expect(find.byKey(const Key('linkEmail.error')), findsOneWidget);
      expect(
        find.text(
          'This email is already linked to a Rihla account. '
          'Restore from that account instead.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('generic network error surfaces a connection-failure message', (
    tester,
  ) async {
    when(
      () => service.linkEmailToCurrentUser(any()),
    ).thenThrow(StateError('boom'));

    await tester.pumpWidget(_wrap(_buildRouter(), service));
    await tester.pumpAndSettle();

    await _typeAndSubmit(
      tester,
      email: 'foo@example.com',
      confirm: 'foo@example.com',
    );

    expect(
      find.text("Couldn't send the link. Check your connection and try again."),
      findsOneWidget,
    );
  });
}
