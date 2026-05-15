import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/router/app_router.dart';

Future<({ProviderContainer container, GoRouter router})> _makeRouter({
  Map<String, Object> prefsSeed = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsSeed);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  final router = container.read(routerProvider);
  return (container: container, router: router);
}

void main() {
  test('splash redirects directly to home for the shippable v1 surface', () {
    expect(appRouteRedirect(AppRoutes.splash), AppRoutes.home);
  });

  test('invite links are not gated by onboarding state', () {
    expect(appRouteRedirect(AppRoutes.joinInvite), isNull);
  });

  test('onboarding route is not part of the shippable route tree', () async {
    final harness = await _makeRouter(
      prefsSeed: const {'settings_onboarding_complete': false},
    );
    addTearDown(harness.router.dispose);
    addTearDown(harness.container.dispose);

    final match = harness.router.configuration.findMatch('/onboarding');

    expect(match.isError, isTrue);
  });

  test('join invite route remains addressable on a fresh install', () async {
    final harness = await _makeRouter(
      prefsSeed: const {'settings_onboarding_complete': false},
    );
    addTearDown(harness.router.dispose);
    addTearDown(harness.container.dispose);

    final match = harness.router.configuration.findMatch('/join/ABC123');

    expect(match.isError, isFalse);
    expect(match.uri.path, '/join/ABC123');
    expect(match.pathParameters['code'], 'ABC123');
  });

  test(
    'registered deep-linkable routes match the production route tree',
    () async {
      final harness = await _makeRouter();
      addTearDown(harness.router.dispose);
      addTearDown(harness.container.dispose);

      const paths = [
        '/home',
        '/profile',
        '/profile/link-email',
        '/profile/link-email/sent',
        '/recover',
        '/recover/pending',
        '/activity',
        '/create-group',
        '/join-group',
        '/join/ABC123',
        '/group/g1',
        '/group/g1/settings',
        '/group/g1/settle-up',
        '/group/g1/activity',
        '/group/g1/create-event',
        '/group/g1/create-event/custom',
        '/group/g1/event/e1',
        '/group/g1/event/e1/ledger',
        '/group/g1/event/e1/ledger/add',
        '/group/g1/event/e1/ledger/edit/x1',
        '/group/g1/event/e1/ledger/settle-up',
        '/group/g1/event/e1/activity',
        '/group/g1/event/e1/settings',
      ];

      for (final path in paths) {
        expect(
          harness.router.configuration.findMatch(path).isError,
          isFalse,
          reason: path,
        );
      }
    },
  );

  test('removed module routes are not registered', () async {
    final harness = await _makeRouter();
    addTearDown(harness.router.dispose);
    addTearDown(harness.container.dispose);

    const removedPaths = [
      '/group/g1/event/e1/gear',
      '/group/g1/event/e1/logistics',
      '/group/g1/event/e1/vault',
      '/group/g1/event/e1/memories',
      '/group/g1/event/e1/memories/m1',
    ];

    for (final path in removedPaths) {
      expect(
        harness.router.configuration.findMatch(path).isError,
        isTrue,
        reason: path,
      );
    }
  });

  test('production navigation avoids imperative pushes and state.extra', () {
    final violations = <String>[];
    final forbidden = {
      'Navigator.push': RegExp(r'Navigator(?:\.of\([^)]*\))?\.push'),
      'state.extra': RegExp(r'\bstate\.extra\b'),
      'pushNamed': RegExp(r'\bpushNamed\s*\('),
      'goNamed': RegExp(r'\bgoNamed\s*\('),
    };

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = entity.readAsStringSync();
      for (final entry in forbidden.entries) {
        if (entry.value.hasMatch(contents)) {
          violations.add('${entity.path}: ${entry.key}');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
