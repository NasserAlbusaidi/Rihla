// Widget tests for the optional durable-credential sheet (#441/#818).
//
// Contract: pops `true` only after linkGoogleToCurrentUser succeeds AND the ID
// token is force-refreshed so observers see the linked credential promptly.
// Conflicts must NEVER be resolved by signing the anon user out (#213).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/auth/widgets/durable_credential_sheet.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

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

  Widget harness({Stream<List<Group>>? groups}) {
    return ProviderScope(
      overrides: [
        authRecoveryServiceProvider.overrideWithValue(recovery),
        if (groups != null) userGroupsProvider.overrideWith((ref) => groups),
      ],
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

  Future<AppLocalizations> open(
    WidgetTester tester, {
    Stream<List<Group>>? groups,
  }) async {
    await tester.pumpWidget(harness(groups: groups));
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
    'conflict on a POPULATED shell shows the dead-end durableGateConflict, '
    'stays open, never pops true (#428: switch flow pinned in '
    'durable_credential_sheet_conflict_test.dart)',
    (tester) async {
      // The harness overrides userGroupsProvider NON-empty on purpose: this
      // pins the populated-shell dead-end branch explicitly rather than
      // riding the error→dead-end fail-safe of the un-overridden provider.
      when(() => recovery.linkGoogleToCurrentUser()).thenThrow(
        GoogleLinkConflictException(
          credential: _FakeAuthCredential(),
          cause: FirebaseAuthException(code: 'credential-already-in-use'),
        ),
      );

      final l10n = await open(
        tester,
        groups: Stream.value([
          Group(
            id: 'g1',
            name: 'Trip',
            inviteCode: 'ABCDEF',
            createdBy: 'u1',
            memberIds: const ['u1'],
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.tap(find.text(l10n.durableGateContinueGoogle));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text(l10n.durableGateConflict), findsOneWidget);
      expect(find.byKey(const Key('durableGate.switch')), findsNothing);
      // The same-UID contract: a conflict is the caller's decision point —
      // nothing in the sheet may sign the anon user out (#213).
      verifyNever(() => recovery.signOutCurrentDevice());
    },
  );

  testWidgets('network failure shows authErrorOffline', (tester) async {
    when(
      () => recovery.linkGoogleToCurrentUser(),
    ).thenThrow(FirebaseAuthException(code: 'network-request-failed'));

    final l10n = await open(tester);
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text(l10n.authErrorOffline), findsOneWidget);
  });

  testWidgets('missing-config StateError shows generic error, stays open', (
    tester,
  ) async {
    when(
      () => recovery.linkGoogleToCurrentUser(),
    ).thenThrow(StateError('GOOGLE_SERVER_CLIENT_ID is not configured'));

    final l10n = await open(tester);
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text(l10n.durableGateError), findsOneWidget);
  });

  // -----------------------------------------------------------------------
  // #1256 iOS Apple parity. Android (the test default platform) must render
  // byte-identical trees to today — the tests above ARE that assertion; the
  // explicit absence check below pins it once more.
  // -----------------------------------------------------------------------

  group('iOS Apple parity (#1256)', () {
    // Safety net for mid-body failures; the happy path resets in-body per
    // the repo convention.
    tearDown(() => debugDefaultTargetPlatformOverride = null);
    const appleKey = Key('durableGate.continueApple');
    const googleKey = Key('durableGate.continue');

    testWidgets('iOS: Apple button renders ABOVE Google with the neutral '
        'body copy', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final l10n = await open(tester);

      expect(find.byKey(appleKey), findsOneWidget);
      expect(find.text(l10n.durableGateBodyIos), findsOneWidget);
      expect(find.text(l10n.durableGateBody), findsNothing);
      final appleDy = tester.getTopLeft(find.byKey(appleKey)).dy;
      final googleDy = tester.getTopLeft(find.byKey(googleKey)).dy;
      expect(
        appleDy,
        lessThan(googleDy),
        reason: 'SiwA HIG + 4.8 parity: Apple must render above Google',
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS: Apple button links Apple, refreshes the token, pops '
        'true', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      when(
        () => recovery.linkAppleToCurrentUser(),
      ).thenAnswer((_) async => credential);

      await open(tester);
      await tester.tap(find.byKey(appleKey));
      await tester.pumpAndSettle();

      verify(() => recovery.linkAppleToCurrentUser()).called(1);
      verify(() => linkedUser.getIdToken(true)).called(1);
      verifyNever(() => recovery.linkGoogleToCurrentUser());
      expect(result, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS: canceled Apple sheet stays open, no error text', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      when(() => recovery.linkAppleToCurrentUser()).thenThrow(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'user canceled',
        ),
      );

      final l10n = await open(tester);
      await tester.tap(find.byKey(appleKey));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text(l10n.durableGateTitle), findsOneWidget);
      expect(find.byKey(const Key('durableGate.error')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS: non-cancel Apple failure shows the generic error', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      when(() => recovery.linkAppleToCurrentUser()).thenThrow(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.failed,
          message: 'authorization failed',
        ),
      );

      final l10n = await open(tester);
      await tester.tap(find.byKey(appleKey));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text(l10n.durableGateError), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('default platform (android): NO Apple button, Google body', (
      tester,
    ) async {
      final l10n = await open(tester);
      expect(find.byKey(appleKey), findsNothing);
      expect(find.text(l10n.durableGateBody), findsOneWidget);
      expect(find.text(l10n.durableGateBodyIos), findsNothing);
    });
  });
}
