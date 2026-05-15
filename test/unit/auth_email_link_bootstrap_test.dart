import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_email_link_config.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';

class _MockAppLinks extends Mock implements AppLinks {}

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUserCredential extends Mock implements UserCredential {}

Uri _validAuthLink() => Uri.parse(
  'https://${AuthEmailLinkConfig.hostingDomain}'
  '${AuthEmailLinkConfig.continuePath}'
  '?mode=signIn&oobCode=ABC123',
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

      // A second link should still be processed — the listener must not
      // collapse on first error.
      when(
        () => service.completeRecovery(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      verify(() => service.completeRecovery(any())).called(2);
    },
  );

  group('link → recover auto-fallback', () {
    for (final code in const [
      'email-already-in-use',
      'credential-already-in-use',
      'provider-already-linked',
    ]) {
      test('opLink failing with $code falls back to completeRecovery', () async {
        when(() => service.readPendingEmail()).thenReturn('foo@example.com');
        when(
          () => service.readInFlightOp(),
        ).thenReturn(AuthRecoveryService.opLink);
        when(
          () => service.completeEmailLink(any()),
        ).thenThrow(FirebaseAuthException(code: code));
        when(
          () => service.completeRecovery(any()),
        ).thenAnswer((_) async => _MockUserCredential());
        await attach();

        uriStream.add(_validAuthLink());
        await pumpEventQueue();

        verify(() => service.completeEmailLink(any())).called(1);
        verify(
          () => service.completeRecovery(_validAuthLink().toString()),
        ).called(1);
      });
    }

    test('successful fallback clears pendingEmailLinkProvider', () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opLink);
      when(
        () => service.completeEmailLink(any()),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      when(
        () => service.completeRecovery(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      await attach();

      container.read(pendingEmailLinkProvider.notifier).state =
          'https://stale-link';
      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      expect(container.read(pendingEmailLinkProvider), isNull);
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
        // Recover failures must not trigger another recover attempt — only
        // link → recover is auto-fallback territory.
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

    test('fallback recover failure does not crash the stream', () async {
      when(() => service.readPendingEmail()).thenReturn('foo@example.com');
      when(
        () => service.readInFlightOp(),
      ).thenReturn(AuthRecoveryService.opLink);
      when(
        () => service.completeEmailLink(any()),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      when(
        () => service.completeRecovery(any()),
      ).thenThrow(FirebaseAuthException(code: 'invalid-action-code'));
      await attach();

      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      // Listener still alive — a second event should still be dispatched.
      when(
        () => service.completeEmailLink(any()),
      ).thenAnswer((_) async => _MockUserCredential());
      uriStream.add(_validAuthLink());
      await pumpEventQueue();

      verify(() => service.completeEmailLink(any())).called(2);
    });
  });
}
