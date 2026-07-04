import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/app_messenger.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/providers/shell_emptiness_gate.dart';
import 'package:safar/features/auth/services/auth_email_link_config.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockAppLinks extends Mock implements AppLinks {}

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockGroupService extends Mock implements GroupService {}

/// A settled outgoing anon shell (the UID that an email RECOVER swap would
/// replace). `#647` gates the swap on this shell being provably empty.
final _anonUser = MockUser(isAnonymous: true, uid: 'anonA');

Group _group() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'anonA',
  memberIds: const ['anonA'],
  createdAt: DateTime(2026, 1, 1),
);

Uri _validAuthLink({String oobCode = 'ABC123'}) => Uri.parse(
  'https://${AuthEmailLinkConfig.hostingDomain}'
  '${AuthEmailLinkConfig.continuePath}'
  '?mode=signIn&oobCode=$oobCode',
);

Uri _customSchemeFallbackLink() => Uri(
  scheme: 'rihla',
  host: 'auth-link',
  queryParameters: {'link': _validAuthLink().toString()},
);

void main() {
  late _MockAppLinks appLinks;
  late _MockRecoveryService service;
  late _MockGroupService groupService;
  late StreamController<Uri> uriStream;
  late ProviderContainer container;

  setUp(() {
    appLinks = _MockAppLinks();
    service = _MockRecoveryService();
    groupService = _MockGroupService();
    uriStream = StreamController<Uri>.broadcast();
    when(() => appLinks.uriLinkStream).thenAnswer((_) => uriStream.stream);
    when(() => appLinks.getInitialLink()).thenAnswer((_) async => null);
    // #647: the recover BLOCK path clears the recovery handshake. Stub so the
    // block tests can `verify` it and the proceed tests are unaffected.
    when(() => service.clearInFlightOp()).thenAnswer((_) async {});
    when(() => service.clearPendingEmail()).thenAnswer((_) async {});
    // Default outgoing shell: settled anon user with NO groups → empty →
    // recover PROCEEDS. Individual tests override watchUserGroups / the user
    // stream to exercise the block + race paths.
    when(
      () => groupService.watchUserGroups(any()),
    ).thenAnswer((_) => Stream.value(const <Group>[]));
  });

  tearDown(() async {
    container.dispose();
    await uriStream.close();
  });

  // Drives the REAL userGroupsProvider through two seams — a controllable
  // `firebaseUserProvider` (so a test can hold the UID in `loading` then settle
  // it AFTER the deep link arrives — the #647 cold-start race) and a mocked
  // `groupServiceProvider` (membership result without Firestore). NOT a direct
  // `userGroupsProvider` override, which would mask the race the gate fixes.
  Future<void> attach({
    Stream<User?>? users,
    Duration gateTimeout = const Duration(seconds: 5),
  }) async {
    container = ProviderContainer(
      overrides: [
        appLinksProvider.overrideWithValue(appLinks),
        authRecoveryServiceProvider.overrideWithValue(service),
        firebaseUserProvider.overrideWith(
          (ref) => users ?? Stream<User?>.value(_anonUser),
        ),
        groupServiceProvider.overrideWithValue(groupService),
        shellEmptinessGateTimeoutProvider.overrideWithValue(gateTimeout),
      ],
    );
    container.read(authEmailLinkBootstrapProvider);
  }

  // The gate chains firebaseUserProvider.future → userGroupsProvider rebuild →
  // watchUserGroups first-emit; a lone pumpEventQueue can under-drain it.
  Future<void> settle([int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('opLink in pendingOp routes to completeEmailLink', () async {
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(() => service.readInFlightOp()).thenReturn(AuthRecoveryService.opLink);
    when(
      () => service.completeEmailLink(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    await attach();

    uriStream.add(_validAuthLink());
    await pumpEventQueue();

    verify(() => service.completeEmailLink(any())).called(1);
    verifyNever(() => service.restoreWithEmailLink(any()));
  });

  test('opRecover in pendingOp routes to restoreWithEmailLink', () async {
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(
      () => service.readInFlightOp(),
    ).thenReturn(AuthRecoveryService.opRecover);
    when(
      () => service.restoreWithEmailLink(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    await attach();

    uriStream.add(_validAuthLink());
    await pumpEventQueue();

    verify(() => service.restoreWithEmailLink(any())).called(1);
    verifyNever(() => service.completeEmailLink(any()));
  });

  test(
    'null inFlightOp defaults to completeEmailLink (legacy/pre-P4)',
    () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(() => service.readInFlightOp()).thenReturn(null);
      when(
        () => service.completeEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      verify(() => service.completeEmailLink(any())).called(1);
    },
  );

  test(
    'missing pending email surfaces the link via pendingEmailLinkProvider',
    () async {
      when(() => service.readPendingEmail()).thenReturn(null);
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      expect(container.read(pendingEmailLinkProvider), isNotNull);
      verifyNever(() => service.completeEmailLink(any()));
      verifyNever(() => service.restoreWithEmailLink(any()));
    },
  );

  test('successful completion clears pendingEmailLinkProvider', () async {
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(() => service.readInFlightOp()).thenReturn(AuthRecoveryService.opLink);
    when(
      () => service.completeEmailLink(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    await attach();

    container.read(pendingEmailLinkProvider.notifier).state =
        'https://stale-link';
    uriStream.add(_validAuthLink());
    await pumpEventQueue();

    expect(container.read(pendingEmailLinkProvider), isNull);
  });

  test('cold-start initial link routes to restoreWithEmailLink', () async {
    when(
      () => appLinks.getInitialLink(),
    ).thenAnswer((_) async => _validAuthLink());
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(
      () => service.readInFlightOp(),
    ).thenReturn(AuthRecoveryService.opRecover);
    when(
      () => service.restoreWithEmailLink(any()),
    ).thenAnswer((_) async => _MockUserCredential());

    await attach();
    await pumpEventQueue();

    verify(() => service.restoreWithEmailLink(any())).called(1);
    verifyNever(() => service.completeEmailLink(any()));
  });

  test('custom-scheme fallback link routes to restoreWithEmailLink', () async {
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(
      () => service.readInFlightOp(),
    ).thenReturn(AuthRecoveryService.opRecover);
    when(
      () => service.restoreWithEmailLink(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    await attach();

    uriStream.add(_customSchemeFallbackLink());
    await pumpEventQueue();

    verify(
      () => service.restoreWithEmailLink(_validAuthLink().toString()),
    ).called(1);
    verifyNever(() => service.completeEmailLink(any()));
  });

  test(
    'FirebaseAuthException during completion does not crash the stream',
    () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opRecover);
      when(
        () => service.restoreWithEmailLink(any()),
      ).thenThrow(FirebaseAuthException(code: 'invalid-action-code'));
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      // A second, distinct link should still be processed — the listener
      // must not collapse on first error. (Same oobCode would be dedupe-
      // suppressed; that's by design and covered in its own test.)
      when(
        () => service.restoreWithEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      uriStream.add(_validAuthLink(oobCode: 'NEXT001'));
      await pumpEventQueue();

      verify(() => service.restoreWithEmailLink(any())).called(2);
    },
  );

  group('link conflict — no auto-recovery (#414)', () {
    for (final code in const [
      'email-already-in-use',
      'credential-already-in-use',
      'provider-already-linked',
    ]) {
      test('opLink failing with $code surfaces the conflict and never calls '
          'restoreWithEmailLink', () async {
        // #414: auto-falling-back to restoreWithEmailLink signs the anon
        // account out and orphans its data. Recovery into the other
        // account is an explicit, consented action via RecoverScreen only.
        when(() => service.readPendingEmail()).thenReturn('foo@example.com');
        when(
          () => service.readInFlightOp(),
        ).thenReturn(AuthRecoveryService.opLink);
        when(
          () => service.completeEmailLink(any()),
        ).thenThrow(FirebaseAuthException(code: code));
        await attach();

        uriStream.add(_validAuthLink());
        await pumpEventQueue();

        verify(() => service.completeEmailLink(any())).called(1);
        verifyNever(() => service.restoreWithEmailLink(any()));
      });
    }

    test('conflict does not clear a stashed pending link', () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opLink);
      when(
        () => service.completeEmailLink(any()),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      await attach();

      container.read(pendingEmailLinkProvider.notifier).state =
          'https://stale-link';
      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      // Error paths leave the §4.7 stash alone — only successful completion
      // clears it.
      expect(container.read(pendingEmailLinkProvider), 'https://stale-link');
    });

    test('conflict error does not crash the stream', () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opLink);
      when(
        () => service.completeEmailLink(any()),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      // Listener still alive — a second, distinct event should still be
      // dispatched. (Repeating the same oobCode is dedupe-suppressed.)
      when(
        () => service.completeEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      uriStream.add(_validAuthLink(oobCode: 'NEXT002'));
      await pumpEventQueue();

      verify(() => service.completeEmailLink(any())).called(2);
      verifyNever(() => service.restoreWithEmailLink(any()));
    });

    test(
      'opLink failing with non-fallback code does NOT call restoreWithEmailLink',
      () async {
        when(() => service.readPendingEmail()).thenReturn('foo@example.com');
        when(
          () => service.readInFlightOp(),
        ).thenReturn(AuthRecoveryService.opLink);
        when(
          () => service.completeEmailLink(any()),
        ).thenThrow(FirebaseAuthException(code: 'invalid-action-code'));
        await attach();

        uriStream.add(_validAuthLink());
        await pumpEventQueue();

        verify(() => service.completeEmailLink(any())).called(1);
        verifyNever(() => service.restoreWithEmailLink(any()));
      },
    );

    test(
      'opRecover failing with email-already-in-use does NOT re-fallback',
      () async {
        // Recover failures surface as errors — they must never dispatch
        // another completion attempt.
        when(() => service.readPendingEmail()).thenReturn('foo@example.com');
        when(
          () => service.readInFlightOp(),
        ).thenReturn(AuthRecoveryService.opRecover);
        when(
          () => service.restoreWithEmailLink(any()),
        ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
        await attach();

        uriStream.add(_validAuthLink());
        await pumpEventQueue();

        verify(() => service.restoreWithEmailLink(any())).called(1);
        verifyNever(() => service.completeEmailLink(any()));
      },
    );
  });

  group('cold-start dedupe', () {
    test(
      'same link emitted by initial + stream is handled only once',
      () async {
        // app_links emits the cold-start URL through BOTH getInitialLink() and
        // uriLinkStream on the same launch. Without dedupe, the second pass
        // clobbers the first's success path with a "no pending email" error
        // (prefs got cleared by the first completion).
        when(
          () => appLinks.getInitialLink(),
        ).thenAnswer((_) async => _validAuthLink());
        when(() => service.readPendingEmail()).thenReturn('foo@example.com');
        when(
          () => service.readInFlightOp(),
        ).thenReturn(AuthRecoveryService.opRecover);
        when(
          () => service.restoreWithEmailLink(any()),
        ).thenAnswer((_) async => _MockUserCredential());

        await attach();
        await pumpEventQueue();

        // Re-emit the same URL via the stream — must be ignored.
        uriStream.add(_validAuthLink());
        await pumpEventQueue();

        verify(() => service.restoreWithEmailLink(any())).called(1);
      },
    );

    test('different oobCodes are processed independently', () async {
      // A second, distinct link in the same session must still be handled.
      final secondLink = Uri.parse(
        'https://${AuthEmailLinkConfig.hostingDomain}'
        '${AuthEmailLinkConfig.continuePath}'
        '?mode=signIn&oobCode=XYZ789',
      );
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opRecover);
      when(
        () => service.restoreWithEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();
      uriStream.add(secondLink);
      await pumpEventQueue();

      verify(() => service.restoreWithEmailLink(any())).called(2);
    });
  });

  // #647 — a populated anon shell must never silently cross-UID swap. The email
  // RECOVER deep link is the one entrance that never consulted the emptiness
  // predicate the Profile/sheet entrances already use. restoreWithEmailLink
  // engages isolation + a guaranteed restart in its finally — it can't be
  // aborted once entered — so the gate must fire BEFORE the call, fail-safe.
  group('#647 cross-UID swap guard (op=recover)', () {
    void stubRecover() {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opRecover);
      when(
        () => service.restoreWithEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
    }

    test(
      'cold-start race: UID settles AFTER dispatch, shell populated → NO swap',
      () async {
        // The P1: on cold-start the deep link can be the FIRST reader of
        // userGroupsProvider while firebaseUserProvider is still loading →
        // uid==null → Stream.value([]) → a FALSE empty. Without the
        // `await firebaseUserProvider.future` this proceeds and orphans the
        // populated shell. RED before the fix (restore called), GREEN after.
        final userController = StreamController<User?>.broadcast();
        addTearDown(userController.close);
        when(
          () => groupService.watchUserGroups(any()),
        ).thenAnswer((_) => Stream.value([_group()]));
        stubRecover();

        await attach(users: userController.stream); // UID held in `loading`
        uriStream.add(_validAuthLink());
        await settle(); // gate now awaits firebaseUserProvider.future
        userController.add(_anonUser); // settle the UID — shell is populated
        await settle();

        verifyNever(() => service.restoreWithEmailLink(any()));
        verify(() => service.clearInFlightOp()).called(1);
      },
    );

    test('settled populated shell → blocks the swap', () async {
      when(
        () => groupService.watchUserGroups(any()),
      ).thenAnswer((_) => Stream.value([_group()]));
      stubRecover();

      await attach();
      uriStream.add(_validAuthLink());
      await settle();

      verifyNever(() => service.restoreWithEmailLink(any()));
    });

    test('settled empty shell → proceeds with the swap', () async {
      // Default watchUserGroups → [] (empty).
      stubRecover();

      await attach();
      uriStream.add(_validAuthLink());
      await settle();

      verify(() => service.restoreWithEmailLink(any())).called(1);
      verifyNever(() => service.clearInFlightOp());
    });

    test('groups stream error → blocks (fail-safe)', () async {
      when(
        () => groupService.watchUserGroups(any()),
      ).thenAnswer((_) => Stream<List<Group>>.error(StateError('boom')));
      stubRecover();

      await attach();
      uriStream.add(_validAuthLink());
      await settle();

      verifyNever(() => service.restoreWithEmailLink(any()));
      verify(() => service.clearInFlightOp()).called(1);
    });

    test('gate hang → blocks (fail-safe on timeout)', () async {
      // firebaseUserProvider never emits → gate await hangs → timeout → block.
      final neverUser = StreamController<User?>.broadcast();
      addTearDown(neverUser.close);
      stubRecover();

      await attach(
        users: neverUser.stream,
        gateTimeout: const Duration(milliseconds: 50),
      );
      uriStream.add(_validAuthLink());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await settle();

      verifyNever(() => service.restoreWithEmailLink(any()));
      verify(() => service.clearInFlightOp()).called(1);
    });

    test('no current user → proceeds (nothing to orphan)', () async {
      stubRecover();

      await attach(users: Stream<User?>.value(null));
      uriStream.add(_validAuthLink());
      await settle();

      verify(() => service.restoreWithEmailLink(any())).called(1);
    });

    test(
      'blocked recover clears the recovery handshake (no phantom op)',
      () async {
        // A blocked recover performed no swap/restart, so the persisted
        // inFlightOp='recover' is a phantom that would keep redispatching.
        when(
          () => groupService.watchUserGroups(any()),
        ).thenAnswer((_) => Stream.value([_group()]));
        stubRecover();

        await attach();
        uriStream.add(_validAuthLink());
        await settle();

        verify(() => service.clearInFlightOp()).called(1);
        verify(() => service.clearPendingEmail()).called(1);
        verifyNever(() => service.restoreWithEmailLink(any()));
      },
    );

    test(
      'guard-rail: op=link conflict (email-already-in-use) never swaps UID',
      () async {
        // completeEmailLink is SAME-UID with no conflict→switch route; the
        // conflict must surface as an error and NEVER fall back to a swap
        // (#414). Pins the safe-by-absence invariant as safe-by-assertion.
        when(() => service.readPendingEmail()).thenReturn('foo@example.com');
        when(
          () => service.readInFlightOp(),
        ).thenReturn(AuthRecoveryService.opLink);
        when(
          () => service.completeEmailLink(any()),
        ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

        await attach();
        uriStream.add(_validAuthLink());
        await settle();

        verify(() => service.completeEmailLink(any())).called(1);
        verifyNever(() => service.restoreWithEmailLink(any()));
      },
    );
  });

  // ---------------------------------------------------------------------
  // #841 PR-3: widget-level l10n test. Every other test in this file drives
  // the bare ProviderContainer (no widget tree), so
  // appMessengerKey.currentContext is always null and every snack silently
  // takes the EN fallback — that would mask total localization failure for
  // AR users. This drives the REAL provider through a real MaterialApp,
  // mirroring the #843 recovery_outcome_notice_test.dart AR widget test.
  // ---------------------------------------------------------------------
  testWidgets('AR l10n: no-pending-email snack shows the localized string', (
    tester,
  ) async {
    when(() => service.readPendingEmail()).thenReturn(null);

    container = ProviderContainer(
      overrides: [
        appLinksProvider.overrideWithValue(appLinks),
        authRecoveryServiceProvider.overrideWithValue(service),
        firebaseUserProvider.overrideWith(
          (ref) => Stream<User?>.value(_anonUser),
        ),
        groupServiceProvider.overrideWithValue(groupService),
        shellEmptinessGateTimeoutProvider.overrideWithValue(
          const Duration(seconds: 5),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          scaffoldMessengerKey: appMessengerKey,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(authEmailLinkBootstrapProvider);
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );
    await tester.pump();

    uriStream.add(_validAuthLink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(find.text(ar.authEmailLinkNoPendingEmail), findsOneWidget);
  });
}
