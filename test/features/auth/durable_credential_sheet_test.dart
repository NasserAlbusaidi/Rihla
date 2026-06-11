// Widget tests for the durable-credential gate sheet (#441 PR2).
//
// The sheet blocks the first create/join until the anon user links a Google
// credential. Contract: pops `true` only after linkGoogleToCurrentUser
// succeeds AND the ID token is force-refreshed (the cached token can still
// carry sign_in_provider=anonymous — the very next write is rules-gated on
// it). Conflicts must NEVER be resolved by signing the anon user out (#213).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/widgets/durable_credential_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

void main() {
  late _MockAuthRecoveryService recovery;
  late _MockUserCredential credential;
  late _MockUser linkedUser;
  bool? result;

  setUp(() {
    recovery = _MockAuthRecoveryService();
    credential = _MockUserCredential();
    linkedUser = _MockUser();
    result = null;
    when(() => credential.user).thenReturn(linkedUser);
    when(() => linkedUser.getIdToken(true)).thenAnswer((_) async => 'fresh');
  });

  Widget harness() {
    return ProviderScope(
      overrides: [authRecoveryServiceProvider.overrideWithValue(recovery)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDurableCredentialSheet(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<AppLocalizations> open(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return tester.element(find.text('open')).l10n;
  }

  testWidgets('renders title, body, and both actions', (tester) async {
    final l10n = await open(tester);
    expect(find.text(l10n.durableGateTitle), findsOneWidget);
    expect(find.text(l10n.durableGateBody), findsOneWidget);
    expect(find.text(l10n.durableGateContinueGoogle), findsOneWidget);
    expect(find.text(l10n.durableGateNotNow), findsOneWidget);
  });

  testWidgets(
    'Continue links Google, force-refreshes the ID token, pops true',
    (tester) async {
      when(
        () => recovery.linkGoogleToCurrentUser(),
      ).thenAnswer((_) async => credential);

      final l10n = await open(tester);
      await tester.tap(find.text(l10n.durableGateContinueGoogle));
      await tester.pumpAndSettle();

      verify(() => recovery.linkGoogleToCurrentUser()).called(1);
      verify(() => linkedUser.getIdToken(true)).called(1);
      expect(result, isTrue);
    },
  );

  testWidgets('Not now pops false', (tester) async {
    final l10n = await open(tester);
    await tester.tap(find.text(l10n.durableGateNotNow));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('barrier dismiss returns false', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('canceled Google sheet stays open, no error text', (
    tester,
  ) async {
    when(() => recovery.linkGoogleToCurrentUser()).thenThrow(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );

    final l10n = await open(tester);
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text(l10n.durableGateTitle), findsOneWidget);
    expect(find.byKey(const Key('durableGate.error')), findsNothing);
  });

  testWidgets(
    'conflict shows durableGateConflict inline, stays open, never pops true',
    (tester) async {
      when(() => recovery.linkGoogleToCurrentUser()).thenThrow(
        FirebaseAuthException(code: 'credential-already-in-use'),
      );

      final l10n = await open(tester);
      await tester.tap(find.text(l10n.durableGateContinueGoogle));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text(l10n.durableGateConflict), findsOneWidget);
      // The same-UID contract: a conflict is the caller's decision point —
      // nothing in the sheet may sign the anon user out (#213).
      verifyNever(() => recovery.signOutCurrentDevice());
    },
  );

  testWidgets('network failure shows authErrorOffline', (tester) async {
    when(() => recovery.linkGoogleToCurrentUser()).thenThrow(
      FirebaseAuthException(code: 'network-request-failed'),
    );

    final l10n = await open(tester);
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text(l10n.authErrorOffline), findsOneWidget);
  });

  testWidgets('missing-config StateError shows generic error, stays open', (
    tester,
  ) async {
    when(() => recovery.linkGoogleToCurrentUser()).thenThrow(
      StateError('GOOGLE_SERVER_CLIENT_ID is not configured'),
    );

    final l10n = await open(tester);
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text(l10n.durableGateError), findsOneWidget);
  });
}
