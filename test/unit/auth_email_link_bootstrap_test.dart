import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/providers/account_job_coordinator_provider.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_email_link_config.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';

class _MockAppLinks extends Mock implements AppLinks {}

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUserCredential extends Mock implements UserCredential {}

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
  late StreamController<Uri> uriStream;
  late ProviderContainer container;

  setUp(() {
    appLinks = _MockAppLinks();
    service = _MockRecoveryService();
    uriStream = StreamController<Uri>.broadcast();
    when(() => appLinks.uriLinkStream).thenAnswer((_) => uriStream.stream);
    when(() => appLinks.getInitialLink()).thenAnswer((_) async => null);

    container = ProviderContainer(
      overrides: [
        appLinksProvider.overrideWithValue(appLinks),
        authRecoveryServiceProvider.overrideWithValue(service),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await uriStream.close();
  });

  Future<void> attach() async {
    container.read(authEmailLinkBootstrapProvider);
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
    verifyNever(() => service.completeRecovery(any()));
  });

  test('opRecover in pendingOp routes to completeRecovery', () async {
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(
      () => service.readInFlightOp(),
    ).thenReturn(AuthRecoveryService.opRecover);
    when(
      () => service.completeRecovery(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    await attach();

    uriStream.add(_validAuthLink());
    await pumpEventQueue();

    verify(() => service.completeRecovery(any())).called(1);
    verifyNever(() => service.completeEmailLink(any()));
  });

  test(
    'successful recovery asks account job coordinator to resume cleanup',
    () async {
      var resumeCalls = 0;
      container.dispose();
      container = ProviderContainer(
        overrides: [
          appLinksProvider.overrideWithValue(appLinks),
          authRecoveryServiceProvider.overrideWithValue(service),
          accountJobDriverProvider.overrideWithValue(
            AccountJobDriver(
              resumeProbe: () async {
                resumeCalls += 1;
                return null;
              },
              advance: (status) async => status,
              routeHome: () {},
            ),
          ),
        ],
      );
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opRecover);
      when(
        () => service.completeRecovery(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      verify(() => service.completeRecovery(any())).called(1);
      expect(resumeCalls, 1);
    },
  );

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
      verifyNever(() => service.completeRecovery(any()));
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

  test('cold-start initial link routes to completeRecovery', () async {
    when(
      () => appLinks.getInitialLink(),
    ).thenAnswer((_) async => _validAuthLink());
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(
      () => service.readInFlightOp(),
    ).thenReturn(AuthRecoveryService.opRecover);
    when(
      () => service.completeRecovery(any()),
    ).thenAnswer((_) async => _MockUserCredential());

    await attach();
    await pumpEventQueue();

    verify(() => service.completeRecovery(any())).called(1);
    verifyNever(() => service.completeEmailLink(any()));
  });

  test('custom-scheme fallback link routes to completeRecovery', () async {
    when(() => service.readPendingEmail()).thenReturn('foo@example.com');
    when(
      () => service.readInFlightOp(),
    ).thenReturn(AuthRecoveryService.opRecover);
    when(
      () => service.completeRecovery(any()),
    ).thenAnswer((_) async => _MockUserCredential());
    await attach();

    uriStream.add(_customSchemeFallbackLink());
    await pumpEventQueue();

    verify(
      () => service.completeRecovery(_validAuthLink().toString()),
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
        () => service.completeRecovery(any()),
      ).thenThrow(FirebaseAuthException(code: 'invalid-action-code'));
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      // A second, distinct link should still be processed — the listener
      // must not collapse on first error. (Same oobCode would be dedupe-
      // suppressed; that's by design and covered in its own test.)
      when(
        () => service.completeRecovery(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      uriStream.add(_validAuthLink(oobCode: 'NEXT001'));
      await pumpEventQueue();

      verify(() => service.completeRecovery(any())).called(2);
    },
  );

  group('link conflict handling', () {
    for (final code in const [
      'email-already-in-use',
      'credential-already-in-use',
      'provider-already-linked',
    ]) {
      test(
        'opLink failing with $code does not call completeRecovery',
        () async {
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
          verifyNever(() => service.completeRecovery(any()));
          final conflict = container.read(authEmailLinkConflictProvider);
          expect(conflict?.email, 'foo@example.com');
          expect(conflict?.code, code);
        },
      );
    }

    test('successful link clears stale conflict state', () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opLink);
      when(
        () => service.completeEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      await attach();

      container
          .read(authEmailLinkConflictProvider.notifier)
          .state = const AuthEmailLinkConflict(
        email: 'foo@example.com',
        link: 'https://stale-link',
        code: 'email-already-in-use',
      );
      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      expect(container.read(authEmailLinkConflictProvider), isNull);
    });

    test(
      'opLink failing with non-fallback code does NOT call completeRecovery',
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
        verifyNever(() => service.completeRecovery(any()));
      },
    );

    test(
      'opRecover failing with email-already-in-use does NOT re-fallback',
      () async {
        // Recover failures must not trigger another recover attempt.
        when(() => service.readPendingEmail()).thenReturn('foo@example.com');
        when(
          () => service.readInFlightOp(),
        ).thenReturn(AuthRecoveryService.opRecover);
        when(
          () => service.completeRecovery(any()),
        ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
        await attach();

        uriStream.add(_validAuthLink());
        await pumpEventQueue();

        verify(() => service.completeRecovery(any())).called(1);
        verifyNever(() => service.completeEmailLink(any()));
      },
    );

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
          () => service.completeRecovery(any()),
        ).thenAnswer((_) async => _MockUserCredential());

        await attach();
        await pumpEventQueue();

        // Re-emit the same URL via the stream — must be ignored.
        uriStream.add(_validAuthLink());
        await pumpEventQueue();

        verify(() => service.completeRecovery(any())).called(1);
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
        () => service.completeRecovery(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();
      uriStream.add(secondLink);
      await pumpEventQueue();

      verify(() => service.completeRecovery(any())).called(2);
    });

    test('link conflict does not crash the stream', () async {
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
      verifyNever(() => service.completeRecovery(any()));
    });
  });
}
