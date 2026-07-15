import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/providers/shell_emptiness_gate.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/widgets/apple_restore_action.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

/// #1256 — the Apple restore is the same irreversible cross-UID discard-shell
/// swap as Google's (#648), so triggerAppleRestore must route through the
/// identical outgoingShellProvablyEmpty gate: call restoreWithApple ONLY when
/// the outgoing shell is provably empty.
class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _MockGroupService extends Mock implements GroupService {}

class _MockUserCredential extends Mock implements UserCredential {}

const _kRestoreButton = Key('test.restore.button');

/// Default gate probe: server-confirmed empty → the proceed path stays live.
Future<bool?> _serverEmptyProbe(String uid) async => false;

Group _group(String id) => Group(
  id: id,
  name: 'Trip',
  inviteCode: 'ABC234',
  createdBy: 'anon-1',
  memberIds: const ['anon-1'],
  currency: 'OMR',
  createdAt: DateTime(2026),
);

void main() {
  late _MockAuthRecoveryService recovery;
  late _MockGroupService groupService;

  setUp(() {
    recovery = _MockAuthRecoveryService();
    groupService = _MockGroupService();
    when(() => recovery.restoreWithApple())
        .thenAnswer((_) async => _MockUserCredential());
  });

  Widget buildApp({
    required Stream<User?> userStream,
    Duration timeout = const Duration(seconds: 5),
    Future<bool?> Function(String uid) probe = _serverEmptyProbe,
  }) {
    return ProviderScope(
      overrides: [
        authRecoveryServiceProvider.overrideWithValue(recovery),
        firebaseUserProvider.overrideWith((ref) => userStream),
        groupServiceProvider.overrideWithValue(groupService),
        shellEmptinessGateTimeoutProvider.overrideWithValue(timeout),
        shellEmptinessServerProbeProvider.overrideWithValue(probe),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              key: _kRestoreButton,
              onPressed: () => triggerAppleRestore(context, ref),
              child: const Text('restore'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'populated shell BLOCKS the Apple restore swap (#648 data-loss guard)',
    (tester) async {
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value([_group('g1')]));

      await tester.pumpWidget(
        buildApp(
          userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pumpAndSettle();

      verifyNever(() => recovery.restoreWithApple());
      expect(
        find.text(AppLocalizationsEn().restoreBlockedHasData),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unresolved user (cold-start false-empty) BLOCKS (fail-safe on timeout)',
    (tester) async {
      final never = StreamController<User?>();
      addTearDown(never.close);
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(buildApp(
        userStream: never.stream,
        timeout: const Duration(milliseconds: 50),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      verifyNever(() => recovery.restoreWithApple());
      expect(
        find.text(AppLocalizationsEn().restoreBlockedHasData),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'empty + resolved shell PROCEEDS with the Apple restore',
    (tester) async {
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(
        buildApp(
          userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pumpAndSettle();

      verify(() => recovery.restoreWithApple()).called(1);
    },
  );

  testWidgets(
    'blocks restore when the stream is cache-empty but the server reports '
    'live data (#1091)',
    (tester) async {
      when(() => groupService.watchUserGroups(any()))
          .thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(
        buildApp(
          userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
          probe: (_) async => true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRestoreButton));
      await tester.pumpAndSettle();

      verifyNever(() => recovery.restoreWithApple());
      expect(
        find.text(AppLocalizationsEn().restoreBlockedHasData),
        findsOneWidget,
      );
    },
  );

  testWidgets('canceled Apple sheet is silent — no snack', (tester) async {
    when(() => groupService.watchUserGroups(any()))
        .thenAnswer((_) => Stream.value(const []));
    when(() => recovery.restoreWithApple()).thenThrow(
      const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'user canceled',
      ),
    );

    await tester.pumpWidget(
      buildApp(
        userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_kRestoreButton));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('non-cancel Apple authorization failure surfaces '
      'restoreAppleFailed', (tester) async {
    when(() => groupService.watchUserGroups(any()))
        .thenAnswer((_) => Stream.value(const []));
    when(() => recovery.restoreWithApple()).thenThrow(
      const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'authorization failed',
      ),
    );

    await tester.pumpWidget(
      buildApp(
        userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_kRestoreButton));
    await tester.pumpAndSettle();

    expect(
      find.text(AppLocalizationsEn().restoreAppleFailed),
      findsOneWidget,
    );
  });

  testWidgets('non-cancel failure surfaces restoreAppleFailed', (
    tester,
  ) async {
    when(() => groupService.watchUserGroups(any()))
        .thenAnswer((_) => Stream.value(const []));
    when(() => recovery.restoreWithApple())
        .thenThrow(StateError('no identityToken'));

    await tester.pumpWidget(
      buildApp(
        userStream: Stream.value(MockUser(isAnonymous: true, uid: 'anon-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_kRestoreButton));
    await tester.pumpAndSettle();

    expect(
      find.text(AppLocalizationsEn().restoreAppleFailed),
      findsOneWidget,
    );
  });
}
