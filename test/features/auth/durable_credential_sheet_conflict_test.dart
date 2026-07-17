// Google-link conflict switch flow (#428 PR-A2).
//
// On GoogleLinkConflictException the sheet offers "switch to that account"
// (discard-shell restore reusing the failed credential) ONLY when
// outgoingShellProvablyEmpty proves the current shell empty. Populated/error ->
// the dead-end copy; loading -> progress. NEVER signOut (#213).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/providers/shell_emptiness_gate.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/auth/widgets/durable_credential_sheet.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _MockGroupService extends Mock implements GroupService {}

class _MockUserCredential extends Mock implements UserCredential {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

Group _group() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'u1',
  memberIds: const ['u1'],
  createdAt: DateTime(2026, 1, 1),
);

/// Default gate probe: server-confirmed empty → the switch-offer (proceed)
/// path stays live. Without an override the unbound default hits `[core/no-app]`
/// → null → block, silently turning every empty-shell offer into a dead-end.
Future<bool?> _serverEmptyProbe(String uid) async => false;

void main() {
  late _MockAuthRecoveryService recovery;
  bool? result;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  setUp(() {
    recovery = _MockAuthRecoveryService();
    result = null;
  });

  GoogleLinkConflictException conflict(AuthCredential credential) =>
      GoogleLinkConflictException(
        credential: credential,
        cause: FirebaseAuthException(code: 'credential-already-in-use'),
      );

  Widget harness({
    required Stream<List<Group>> groups,
    Future<bool?> Function(String uid) probe = _serverEmptyProbe,
  }) {
    return ProviderScope(
      overrides: [
        authRecoveryServiceProvider.overrideWithValue(recovery),
        firebaseUserProvider.overrideWith(
          (ref) => Stream.value(MockUser(uid: 'u1', isAnonymous: true)),
        ),
        userGroupsProvider.overrideWith((ref) => groups),
        shellEmptinessServerProbeProvider.overrideWithValue(probe),
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

  Widget harnessWithRealGroups({
    required Stream<User?> users,
    required GroupService groupService,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return ProviderScope(
      overrides: [
        authRecoveryServiceProvider.overrideWithValue(recovery),
        firebaseUserProvider.overrideWith((ref) => users),
        groupServiceProvider.overrideWithValue(groupService),
        shellEmptinessGateTimeoutProvider.overrideWithValue(timeout),
        shellEmptinessServerProbeProvider.overrideWithValue(_serverEmptyProbe),
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

  Future<AppLocalizations> openAndConflict(
    WidgetTester tester, {
    required Stream<List<Group>> groups,
    AuthCredential? credential,
    Future<bool?> Function(String uid) probe = _serverEmptyProbe,
  }) async {
    when(
      () => recovery.linkGoogleToCurrentUser(),
    ).thenThrow(conflict(credential ?? _FakeAuthCredential()));
    await tester.pumpWidget(harness(groups: groups, probe: probe));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = tester.element(find.text('open')).l10n;
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    // Bounded pumps: conflict-loading / _restoring spinners animate forever,
    // so pumpAndSettle would time out on those states.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return l10n;
  }

  Future<AppLocalizations> openAndConflictWithRealGroups(
    WidgetTester tester, {
    required Stream<User?> users,
    required GroupService groupService,
    Duration timeout = const Duration(seconds: 5),
    AuthCredential? credential,
  }) async {
    when(
      () => recovery.linkGoogleToCurrentUser(),
    ).thenThrow(conflict(credential ?? _FakeAuthCredential()));
    await tester.pumpWidget(
      harnessWithRealGroups(
        users: users,
        groupService: groupService,
        timeout: timeout,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = tester.element(find.text('open')).l10n;
    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return l10n;
  }

  testWidgets('conflict + zero groups -> switch offer', (tester) async {
    final l10n = await openAndConflict(tester, groups: Stream.value(const []));

    expect(find.byKey(const Key('durableGate.switch')), findsOneWidget);
    expect(find.text(l10n.durableGateConflictTitle), findsOneWidget);
    expect(find.text(l10n.durableGateConflictSwitchBody), findsOneWidget);
    expect(find.text(l10n.durableGateUseDifferent), findsOneWidget);
    expect(result, isNull);
    verifyNever(() => recovery.signOutCurrentDevice());
  });

  testWidgets(
    'conflict + unresolved user does not false-empty into a switch offer',
    (tester) async {
      final userController = StreamController<User?>.broadcast();
      final groupService = _MockGroupService();
      addTearDown(userController.close);
      when(
        () => groupService.watchUserGroups(any()),
      ).thenAnswer((_) => Stream.value([_group()]));
      when(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      ).thenAnswer((_) async => _MockUserCredential());

      final l10n = await openAndConflictWithRealGroups(
        tester,
        users: userController.stream,
        groupService: groupService,
        timeout: const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();

      expect(find.byKey(const Key('durableGate.switch')), findsNothing);
      expect(find.text(l10n.durableGateConflict), findsOneWidget);
      verifyNever(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      );
    },
  );

  testWidgets('switch reuses the failed credential and never signs out', (
    tester,
  ) async {
    final credential = _FakeAuthCredential();
    when(
      () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
    ).thenAnswer((_) async => _MockUserCredential());

    final l10n = await openAndConflict(
      tester,
      groups: Stream.value(const []),
      credential: credential,
    );

    await tester.tap(find.byKey(const Key('durableGate.switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    verify(() => recovery.restoreWithGoogle(credential: credential)).called(1);
    expect(
      result,
      isNull,
      reason: 'sheet never pops; production restarts here',
    );
    expect(l10n.durableGateSwitch, isNotEmpty);
    verifyNever(() => recovery.signOutCurrentDevice());
  });

  testWidgets(
    'switch re-check blocks if shell becomes populated after the offer renders',
    (tester) async {
      final credential = _FakeAuthCredential();
      final groupService = _MockGroupService();
      final groupsController = StreamController<List<Group>>.broadcast();
      addTearDown(groupsController.close);
      when(
        () => groupService.watchUserGroups(any()),
      ).thenAnswer((_) => groupsController.stream);
      when(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      ).thenAnswer((_) async => _MockUserCredential());

      await openAndConflictWithRealGroups(
        tester,
        users: Stream.value(MockUser(uid: 'u1', isAnonymous: true)),
        groupService: groupService,
        credential: credential,
      );

      groupsController.add(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('durableGate.switch')), findsOneWidget);

      groupsController.add([_group()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('durableGate.switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verifyNever(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      );
      verifyNever(() => recovery.signOutCurrentDevice());
    },
  );

  testWidgets('conflict + populated shell -> dead-end copy, no switch', (
    tester,
  ) async {
    final l10n = await openAndConflict(
      tester,
      groups: Stream.value([_group()]),
    );

    expect(find.byKey(const Key('durableGate.switch')), findsNothing);
    expect(find.text(l10n.durableGateConflict), findsOneWidget);
    verifyNever(
      () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
    );
  });

  testWidgets(
    'conflict + cache-empty stream but server reports live data -> no switch '
    '(#1091)',
    (tester) async {
      // Cold/reinstall device: local cache serves an EMPTY groups snapshot, but
      // the server holds a live membership. The conflict switch must stay
      // blocked — stream-empty is not account-empty.
      final l10n = await openAndConflict(
        tester,
        groups: Stream.value(const []),
        probe: (_) async => true,
      );

      expect(find.byKey(const Key('durableGate.switch')), findsNothing);
      expect(find.text(l10n.durableGateConflict), findsOneWidget);
      verifyNever(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      );
    },
  );

  testWidgets('conflict + groups error -> dead-end copy (fail-safe)', (
    tester,
  ) async {
    final l10n = await openAndConflict(
      tester,
      groups: Stream.error(Exception('no-app')),
    );

    expect(find.byKey(const Key('durableGate.switch')), findsNothing);
    expect(find.text(l10n.durableGateConflict), findsOneWidget);
  });

  testWidgets(
    'conflict + groups still loading -> progress, no dead-end advice',
    (tester) async {
      // A stream that completes without emitting keeps the provider in loading.
      final l10n = await openAndConflict(
        tester,
        groups: const Stream<List<Group>>.empty(),
      );

      expect(find.byKey(const Key('durableGate.switch')), findsNothing);
      expect(find.text(l10n.durableGateConflict), findsNothing);
      expect(
        find.byKey(const Key('durableGate.conflictLoading')),
        findsOneWidget,
      );
    },
  );

  testWidgets('"Use a different account" returns to the initial state', (
    tester,
  ) async {
    final l10n = await openAndConflict(tester, groups: Stream.value(const []));

    await tester.tap(find.text(l10n.durableGateUseDifferent));
    await tester.pumpAndSettle();

    expect(find.text(l10n.durableGateTitle), findsOneWidget);
    expect(find.text(l10n.durableGateContinueGoogle), findsOneWidget);
    expect(find.byKey(const Key('durableGate.switch')), findsNothing);
    expect(result, isNull);
    verifyNever(() => recovery.signOutCurrentDevice());
  });

  testWidgets('provider-already-linked pops true (already durable)', (
    tester,
  ) async {
    when(
      () => recovery.linkGoogleToCurrentUser(),
    ).thenThrow(FirebaseAuthException(code: 'provider-already-linked'));
    await tester.pumpWidget(harness(groups: Stream.value(const [])));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = tester.element(find.text('open')).l10n;

    await tester.tap(find.text(l10n.durableGateContinueGoogle));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('failed restore (pre-isolation throw) resets to generic error', (
    tester,
  ) async {
    when(
      () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
    ).thenThrow(StateError('fcm remove failed'));

    final l10n = await openAndConflict(tester, groups: Stream.value(const []));
    await tester.tap(find.byKey(const Key('durableGate.switch')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text(l10n.durableGateError), findsOneWidget);
    verifyNever(() => recovery.signOutCurrentDevice());
  });

  testWidgets(
    'PendingWritesNotFlushedException on switch clears the conflict and '
    'renders the still-syncing copy (#1281) — no Sentry capture',
    (tester) async {
      when(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      ).thenThrow(PendingWritesNotFlushedException(const Duration(seconds: 5)));

      // Primes BOTH shell gates empty: the build-time _conflictShellEmpty (via
      // the harness()'s userGroupsProvider/firebaseUserProvider overrides) AND
      // _switchAccount's own _outgoingShellEmpty() re-check, which reads the
      // SAME overridden providers.
      final l10n = await openAndConflict(tester, groups: Stream.value(const []));
      expect(find.byKey(const Key('durableGate.switch')), findsOneWidget);

      await tester.tap(find.byKey(const Key('durableGate.switch')));
      await tester.pumpAndSettle();

      // Decision 6: the conflict is cleared so build() takes the
      // `conflict == null` branch, where _errorText actually renders.
      expect(result, isNull);
      expect(
        find.byKey(const Key('durableGate.error')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.restorePendingWritesNotSynced),
        findsOneWidget,
      );
      expect(find.byKey(const Key('durableGate.switch')), findsNothing);
      verifyNever(() => recovery.signOutCurrentDevice());
    },
  );

  // -----------------------------------------------------------------------
  // #1256 Apple-conflict dispatch. An AppleLinkConflictException must route
  // the switch to restoreWithApple with the SAME failed credential and render
  // the Apple copy — a mis-route into restoreWithGoogle is the #414/#647
  // wrong-account swap class the sealed hierarchy exists to prevent.
  // -----------------------------------------------------------------------

  group('Apple conflict (#1256, iOS)', () {
    // Safety net for mid-body failures; the happy path resets in-body per
    // the repo convention.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    AppleLinkConflictException appleConflict(AuthCredential credential) =>
        AppleLinkConflictException(
          credential: credential,
          cause: FirebaseAuthException(code: 'credential-already-in-use'),
        );

    Future<AppLocalizations> openAndAppleConflict(
      WidgetTester tester, {
      required Stream<List<Group>> groups,
      AuthCredential? credential,
    }) async {
      when(
        () => recovery.linkAppleToCurrentUser(),
      ).thenThrow(appleConflict(credential ?? _FakeAuthCredential()));
      await tester.pumpWidget(harness(groups: groups));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n = tester.element(find.text('open')).l10n;
      await tester.tap(find.byKey(const Key('durableGate.continueApple')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return l10n;
    }

    testWidgets('Apple conflict + zero groups -> switch offer with the Apple '
        'copy', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final l10n = await openAndAppleConflict(
        tester,
        groups: Stream.value(const []),
      );

      expect(find.byKey(const Key('durableGate.switch')), findsOneWidget);
      expect(
        find.text(l10n.durableGateConflictSwitchBodyApple),
        findsOneWidget,
      );
      expect(find.text(l10n.durableGateConflictSwitchBody), findsNothing);
      verifyNever(() => recovery.signOutCurrentDevice());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Apple switch reuses the SAME failed credential via '
        'restoreWithApple, never restoreWithGoogle', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final credential = _FakeAuthCredential();
      when(
        () => recovery.restoreWithApple(credential: any(named: 'credential')),
      ).thenAnswer((_) async => _MockUserCredential());

      await openAndAppleConflict(
        tester,
        groups: Stream.value(const []),
        credential: credential,
      );
      await tester.tap(find.byKey(const Key('durableGate.switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => recovery.restoreWithApple(credential: credential))
          .called(1);
      verifyNever(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      );
      verifyNever(() => recovery.signOutCurrentDevice());
      expect(result, isNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Apple conflict + populated shell -> Apple dead-end copy', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final l10n = await openAndAppleConflict(
        tester,
        groups: Stream.value([_group()]),
      );

      expect(find.byKey(const Key('durableGate.switch')), findsNothing);
      expect(find.text(l10n.durableGateConflictApple), findsOneWidget);
      expect(find.text(l10n.durableGateConflict), findsNothing);
      verifyNever(
        () => recovery.restoreWithApple(credential: any(named: 'credential')),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
