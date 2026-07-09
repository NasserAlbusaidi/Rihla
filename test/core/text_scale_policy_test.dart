import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/app_bootstrap_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/router/app_router.dart';
import 'package:safar/core/services/deep_link_service.dart';
import 'package:safar/main.dart';

void main() {
  const appLinksMethodChannel = MethodChannel(
    'com.llfbandit.app_links/messages',
  );
  const appLinksEventChannel = EventChannel(
    'com.llfbandit.app_links/events',
  );
  const probeKey = Key('text-scale-policy-probe');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The iOS branch skips the Android-only install-referrer channel after the
    // cold-start coordinator resolves app links.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      appLinksMethodChannel,
      (call) async => null,
    );
    messenger.setMockStreamHandler(
      appLinksEventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() async {
    await DeepLinkService.instance.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('SafarApp clamps inherited 3.0x text scaling to 1.5x (#1064)', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Text('scale probe', key: probeKey),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view).copyWith(
          textScaler: const TextScaler.linear(3.0),
        ),
        child: ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            routerProvider.overrideWith((ref) => router),
            appBootstrapProvider.overrideWith((ref) {}),
          ],
          child: const SafarApp(),
        ),
      ),
    );
    // Bounded pump: the app-links cold-start window completes without waiting
    // on process-lifetime connectivity timers.
    await tester.pump(const Duration(milliseconds: 300));

    final probeContext = tester.element(find.byKey(probeKey));
    final effectiveScaler = MediaQuery.textScalerOf(probeContext);
    expect(effectiveScaler.scale(100), 150.0);

    // The binding asserts all foundation debug variables are reset BEFORE
    // tearDown callbacks run, so the platform override must clear in-body.
    debugDefaultTargetPlatformOverride = null;
  });
}
