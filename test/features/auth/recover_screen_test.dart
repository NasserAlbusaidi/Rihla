import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/screens/recover_screen.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockFirebaseAuth extends Mock implements firebase_auth.FirebaseAuth {}

class _PendingScreen extends StatelessWidget {
  const _PendingScreen({required this.email});
  final String email;
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('PENDING:$email'));
  }
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/recover',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/recover',
        builder: (_, _) => const RecoverScreen(),
        routes: [
          GoRoute(
            path: 'pending',
            builder: (_, state) =>
                _PendingScreen(email: state.uri.queryParameters['email'] ?? ''),
          ),
        ],
      ),
    ],
  );
}

Widget _wrap({
  required _MockRecoveryService service,
  required _MockFirebaseAuth firebaseAuth,
  required SharedPreferences prefs,
}) {
  return ProviderScope(
    overrides: [
      authRecoveryServiceProvider.overrideWithValue(service),
      firebaseAuthProvider.overrideWithValue(firebaseAuth),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _buildRouter(),
    ),
  );
}

Future<void> _typeAndSubmit(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const Key('recover.email')), email);
  await tester.tap(find.byKey(const Key('recover.submit')));
  await tester.pumpAndSettle();
}

void main() {
  late _MockRecoveryService service;
  late _MockFirebaseAuth firebaseAuth;
  late SharedPreferences prefs;

  setUp(() async {
    service = _MockRecoveryService();
    firebaseAuth = _MockFirebaseAuth();
    when(() => firebaseAuth.signOut()).thenAnswer((_) async {});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('rejects empty email', (tester) async {
    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, prefs: prefs),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recover.submit')));
    await tester.pump();

    expect(find.text('Enter your email.'), findsWidgets);
    verifyNever(() => service.sendRecoveryLink(any()));
  });

  testWidgets('direct entry back button routes home', (tester) async {
    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, prefs: prefs),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.arrow_left_2));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('happy path sends, routes to pending, and shows NO consent '
      'dialog (#441 PR4 — no merge to consent to)', (tester) async {
    when(() => service.sendRecoveryLink(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, prefs: prefs),
    );
    await tester.pumpAndSettle();

    await _typeAndSubmit(tester, '  Foo@Example.COM ');

    verify(() => service.sendRecoveryLink('foo@example.com')).called(1);
    expect(find.text('PENDING:foo@example.com'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(() => firebaseAuth.signOut());
  });

  testWidgets('does NOT mark persistence dirty on the recover screen', (
    tester,
  ) async {
    when(() => service.sendRecoveryLink(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, prefs: prefs),
    );
    await tester.pumpAndSettle();

    await _typeAndSubmit(tester, 'foo@example.com');

    // Sending a link must not touch the cache: restoreWithEmailLink marks
    // dirty itself right before its own restart. Marking here would wipe a
    // cache that is still this user's.
    expect(prefs.getBool(kFirestorePersistenceDirtyKey), isNull);
  });

  testWidgets('user-not-found surfaces the FR-REC-5 message', (tester) async {
    when(
      () => service.sendRecoveryLink(any()),
    ).thenThrow(firebase_auth.FirebaseAuthException(code: 'user-not-found'));

    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, prefs: prefs),
    );
    await tester.pumpAndSettle();

    await _typeAndSubmit(tester, 'unknown@example.com');

    expect(
      find.text(
        "We couldn't find a Rihla account with this email. "
        'Make sure you linked it on your previous device first.',
      ),
      findsOneWidget,
    );
  });
}
