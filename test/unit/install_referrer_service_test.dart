import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/install_referrer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockGoRouter extends Mock implements GoRouter {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockGoRouter router;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    router = _MockGoRouter();
    when(() => router.go(any())).thenReturn(null);
  });

  InstallReferrerService service({
    required Future<String?> Function() read,
    bool isAndroid = true,
    Duration nativeReadTimeout = const Duration(milliseconds: 750),
  }) {
    return InstallReferrerService(
      readRawReferrer: read,
      isAndroid: () => isAndroid,
      nativeReadTimeout: nativeReadTimeout,
    );
  }

  group('InstallReferrerService.parseInviteCode', () {
    test('normalizes decoded and encoded invite payloads', () {
      expect(InstallReferrerService.parseInviteCode('code=abc123'), 'ABC123');
      expect(InstallReferrerService.parseInviteCode('code%3DABC123'), 'ABC123');
    });

    test('accepts unrelated marketing params around a single code', () {
      expect(
        InstallReferrerService.parseInviteCode('utm_source=x&code=ABC123'),
        'ABC123',
      );
      expect(
        InstallReferrerService.parseInviteCode('code=ABC123&utm_source=x'),
        'ABC123',
      );
    });

    test(
      'rejects missing invalid absolute malformed and duplicate code values',
      () {
        expect(InstallReferrerService.parseInviteCode(''), isNull);
        expect(InstallReferrerService.parseInviteCode('utm_source=x'), isNull);
        expect(InstallReferrerService.parseInviteCode('code=ABC12'), isNull);
        expect(InstallReferrerService.parseInviteCode('code=ABC-12'), isNull);
        expect(
          InstallReferrerService.parseInviteCode(
            'https://rihla-safar.web.app/join/ABC123?code=ABC123',
          ),
          isNull,
        );
        expect(InstallReferrerService.parseInviteCode('code%'), isNull);
        expect(
          InstallReferrerService.parseInviteCode('code=ABC123&code=DEF456'),
          isNull,
        );
        expect(
          InstallReferrerService.parseInviteCode('code=ABC123&code=ABC123'),
          isNull,
        );
      },
    );
  });

  test('valid referrer routes once and persists the consumed code', () async {
    final subject = service(read: () async => 'code=abc123');

    expect(
      await subject.consumeDeferredInvite(router, prefs, route: true),
      isTrue,
    );
    expect(
      prefs.getString(InstallReferrerService.consumedCodePrefsKey),
      'ABC123',
    );
    verify(() => router.go('/join/ABC123')).called(1);

    expect(
      await subject.consumeDeferredInvite(router, prefs, route: true),
      isFalse,
    );
    verifyNever(() => router.go('/join/ABC123'));
  });

  test('suppressed valid referrer is consumed without routing', () async {
    final subject = service(read: () async => 'code=OLD111');

    expect(
      await subject.consumeDeferredInvite(router, prefs, route: false),
      isFalse,
    );
    expect(
      prefs.getString(InstallReferrerService.consumedCodePrefsKey),
      'OLD111',
    );
    verifyNever(() => router.go(any()));

    expect(
      await subject.consumeDeferredInvite(router, prefs, route: true),
      isFalse,
    );
    verifyNever(() => router.go(any()));
  });

  test(
    'invalid native null non-Android and timeout are silent no-ops',
    () async {
      expect(
        await service(
          read: () async => null,
        ).consumeDeferredInvite(router, prefs, route: true),
        isFalse,
      );
      expect(
        await service(
          read: () async => 'code=BAD',
          isAndroid: false,
        ).consumeDeferredInvite(router, prefs, route: true),
        isFalse,
      );
      expect(
        await service(
          read: () => Completer<String?>().future,
          nativeReadTimeout: Duration.zero,
        ).consumeDeferredInvite(router, prefs, route: true),
        isFalse,
      );
      expect(
        prefs.getString(InstallReferrerService.consumedCodePrefsKey),
        isNull,
      );
      verifyNever(() => router.go(any()));
    },
  );
}
