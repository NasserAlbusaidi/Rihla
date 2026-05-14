import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/screens/recover_screen.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

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
        path: '/recover',
        builder: (_, _) => const RecoverScreen(),
        routes: [
          GoRoute(
            path: 'pending',
            builder: (_, state) =>
                _PendingScreen(email: state.extra as String? ?? ''),
          ),
        ],
      ),
    ],
  );
}

Widget _wrap({
  required _MockRecoveryService service,
  required _MockFirebaseAuth firebaseAuth,
  required List<Group> groups,
}) {
  return ProviderScope(
    overrides: [
      authRecoveryServiceProvider.overrideWithValue(service),
      firebaseAuthProvider.overrideWithValue(firebaseAuth),
      userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: _buildRouter(),
    ),
  );
}

Group _stubGroup(String id) => Group(
      id: id,
      name: 'Group $id',
      inviteCode: 'INV',
      createdBy: 'someone',
      memberIds: const ['someone'],
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _typeAndSubmit(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(const Key('recover.email')), email);
  await tester.tap(find.byKey(const Key('recover.submit')));
  await tester.pumpAndSettle();
}

void main() {
  late _MockRecoveryService service;
  late _MockFirebaseAuth firebaseAuth;

  setUp(() {
    service = _MockRecoveryService();
    firebaseAuth = _MockFirebaseAuth();
    when(() => firebaseAuth.signOut()).thenAnswer((_) async {});
  });

  testWidgets('rejects empty email', (tester) async {
    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, groups: []),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recover.submit')));
    await tester.pump();

    expect(find.text('Enter your email.'), findsWidgets);
    verifyNever(() => service.sendRecoveryLink(any()));
  });

  testWidgets('happy path on a fresh device sends and routes to pending', (tester) async {
    when(() => service.sendRecoveryLink(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, groups: []),
    );
    await tester.pumpAndSettle();

    await _typeAndSubmit(tester, '  Foo@Example.COM ');

    verify(() => service.sendRecoveryLink('foo@example.com')).called(1);
    expect(find.text('PENDING:foo@example.com'), findsOneWidget);
    verifyNever(() => firebaseAuth.signOut());
  });

  testWidgets('on a populated device, cancelling the dialog blocks the send',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        service: service,
        firebaseAuth: firebaseAuth,
        groups: [_stubGroup('g1')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('recover.email')),
      'foo@example.com',
    );
    await tester.tap(find.byKey(const Key('recover.submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signOutFirst.cancel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('signOutFirst.cancel')));
    await tester.pumpAndSettle();

    verifyNever(() => service.sendRecoveryLink(any()));
    verifyNever(() => firebaseAuth.signOut());
  });

  testWidgets('on a populated device, confirming signs out then proceeds',
      (tester) async {
    when(() => service.sendRecoveryLink(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      _wrap(
        service: service,
        firebaseAuth: firebaseAuth,
        groups: [_stubGroup('g1')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('recover.email')),
      'foo@example.com',
    );
    await tester.tap(find.byKey(const Key('recover.submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('signOutFirst.confirm')));
    await tester.pumpAndSettle();

    verify(() => firebaseAuth.signOut()).called(1);
    verify(() => service.sendRecoveryLink('foo@example.com')).called(1);
    expect(find.text('PENDING:foo@example.com'), findsOneWidget);
  });

  testWidgets('user-not-found surfaces the FR-REC-5 message', (tester) async {
    when(() => service.sendRecoveryLink(any())).thenThrow(
      firebase_auth.FirebaseAuthException(code: 'user-not-found'),
    );

    await tester.pumpWidget(
      _wrap(service: service, firebaseAuth: firebaseAuth, groups: []),
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
