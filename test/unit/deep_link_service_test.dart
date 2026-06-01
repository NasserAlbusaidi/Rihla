import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/deep_link_service.dart';

class _MockAppLinks extends Mock implements AppLinks {}

class _MockGoRouter extends Mock implements GoRouter {}

void main() {
  group('DeepLinkService.parseJoinLink', () {
    final service = DeepLinkService.instance;

    Uri? parse(String link) => service.parseJoinLink(Uri.parse(link));

    test('normalizes custom scheme query join links', () {
      expect(parse('rihla://join?code=ABC123'), Uri(path: '/join/ABC123'));
    });

    test('normalizes custom scheme path join links', () {
      expect(parse('rihla://join/ABC123'), Uri(path: '/join/ABC123'));
    });

    test('normalizes universal link path join links', () {
      expect(
        parse('https://rihla-safar.web.app/join/ABC123'),
        Uri(path: '/join/ABC123'),
      );
      expect(
        parse('https://rihla-safar.firebaseapp.com/join/ABC123'),
        Uri(path: '/join/ABC123'),
      );
    });

    test('normalizes universal link query join links', () {
      expect(
        parse('https://rihla-safar.web.app/join?code=ABC123'),
        Uri(path: '/join/ABC123'),
      );
    });

    test('compares scheme and host case-insensitively', () {
      expect(parse('RIHLA://JOIN/abc123'), Uri(path: '/join/ABC123'));
      expect(
        parse('HTTPS://RIHLA-SAFAR.WEB.APP/join/abc123'),
        Uri(path: '/join/ABC123'),
      );
    });

    test('trims and uppercases invite codes', () {
      expect(
        parse('https://rihla-safar.web.app/join?code=%20abc123%20'),
        Uri(path: '/join/ABC123'),
      );
    });

    test(
      'uses the path segment when both segment and query code are present',
      () {
        expect(
          parse('https://rihla-safar.web.app/join/abc123?code=ZZZ999'),
          Uri(path: '/join/ABC123'),
        );
      },
    );

    test('accepts trailing slashes from browser-normalized invite links', () {
      expect(
        parse('https://rihla-safar.web.app/join/ABC123/'),
        Uri(path: '/join/ABC123'),
      );
      expect(
        parse('https://rihla-safar.web.app/join/?code=abc123'),
        Uri(path: '/join/ABC123'),
      );
      expect(parse('rihla://join/abc123/'), Uri(path: '/join/ABC123'));
    });

    test('rejects non-join links', () {
      expect(parse('safar://join?code=ABC123'), isNull);
      expect(parse('https://example.com/join/ABC123'), isNull);
      expect(parse('https://rihla-safar.web.app/groups/ABC123'), isNull);
    });

    test('rejects missing or empty invite codes', () {
      expect(parse('rihla://join'), isNull);
      expect(parse('rihla://join?code='), isNull);
      expect(parse('https://rihla-safar.web.app/join'), isNull);
      expect(parse('https://rihla-safar.web.app/join?code='), isNull);
    });

    test('rejects invalid invite code formats', () {
      expect(parse('rihla://join?code=ABC12'), isNull);
      expect(parse('rihla://join?code=ABC1234'), isNull);
      expect(parse('rihla://join?code=ABC-12'), isNull);
      expect(parse('https://rihla-safar.web.app/join/ABC_12'), isNull);
    });

    test('rejects the retired rihla.app universal-link host (#130)', () {
      expect(parse('https://rihla.app/join/ABC123'), isNull);
      expect(parse('https://rihla.app/join?code=ABC123'), isNull);
    });
  });

  group('DeepLinkService.init', () {
    late _MockAppLinks appLinks;
    late _MockGoRouter router;
    late StreamController<Uri> uriLinks;
    late DeepLinkService service;

    setUp(() {
      appLinks = _MockAppLinks();
      router = _MockGoRouter();
      uriLinks = StreamController<Uri>.broadcast();
      service = DeepLinkService.withAppLinks(appLinks);
      when(() => appLinks.uriLinkStream).thenAnswer((_) => uriLinks.stream);
      when(() => appLinks.getInitialLink()).thenAnswer((_) async => null);
      when(() => router.go(any())).thenReturn(null);
    });

    tearDown(() async {
      await service.dispose();
      await uriLinks.close();
    });

    test('opens a cold-start join link', () async {
      when(() => appLinks.getInitialLink()).thenAnswer(
        (_) async => Uri.parse('https://rihla-safar.web.app/join/abc123'),
      );

      await service.init(router);

      verify(() => router.go('/join/ABC123')).called(1);
    });

    test('opens runtime join links from the app link stream', () async {
      await service.init(router);

      uriLinks.add(Uri.parse('rihla://join/def456'));
      await Future<void>.delayed(Duration.zero);

      verify(() => router.go('/join/DEF456')).called(1);
    });

    test(
      'does not attach duplicate listeners after repeated init calls',
      () async {
        await service.init(router);
        await service.init(router);

        verify(() => appLinks.uriLinkStream).called(1);
        verify(() => appLinks.getInitialLink()).called(1);
      },
    );

    test('dispose stops runtime link handling', () async {
      await service.init(router);
      await service.dispose();

      uriLinks.add(Uri.parse('rihla://join/ghi789'));
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => router.go(any()));
    });

    test('reports cold-start link failures through FlutterError', () async {
      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = originalOnError);
      when(() => appLinks.getInitialLink()).thenAnswer(
        (_) => Future<Uri?>.error(StateError('boom'), StackTrace.current),
      );

      await service.init(router);

      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'deep_link_service');
    });

    test('reports runtime link stream failures through FlutterError', () async {
      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = originalOnError);
      await service.init(router);

      uriLinks.addError(StateError('stream boom'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'deep_link_service');
    });
  });
}
