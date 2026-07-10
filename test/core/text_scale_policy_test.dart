import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/app_bootstrap_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/router/app_router.dart';
import 'package:safar/core/services/deep_link_service.dart';
import 'package:safar/features/settings/widgets/profile_display_section.dart';
import 'package:safar/main.dart';
import 'package:safar/shared/widgets/section_header.dart';

import '../helpers/pump_rihla_app.dart';

void main() {
  group('SafarApp clamp (#1064)', () {
    const appLinksMethodChannel = MethodChannel(
      'com.llfbandit.app_links/messages',
    );
    const appLinksEventChannel = EventChannel(
      'com.llfbandit.app_links/events',
    );
    const probeKey = Key('text-scale-policy-probe');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // The iOS branch skips the Android-only install-referrer channel after
      // the cold-start coordinator resolves app links.
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
      // Bounded pump: the app-links cold-start window completes without
      // waiting on process-lifetime connectivity timers.
      await tester.pump(const Duration(milliseconds: 300));

      final probeContext = tester.element(find.byKey(probeKey));
      final effectiveScaler = MediaQuery.textScalerOf(probeContext);
      expect(effectiveScaler.scale(100), 150.0);

      // The binding asserts all foundation debug variables are reset BEFORE
      // tearDown callbacks run, so the platform override must clear in-body.
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('1.5x layout hardening (#1076)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget scaledTo15x(Widget child) {
      return Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
          ),
          child: child,
        ),
      );
    }

    testWidgets(
      'Profile Display Theme tile keeps its label on one line at 1.5x with '
      'theme=System (#1076)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await pumpRihlaApp(
          tester,
          scaledTo15x(const Scaffold(body: ProfileDisplaySection())),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'the Theme tile row must not overflow at 1.5x',
        );

        // One line at 1.5x is 14 * 1.5 = 21px tall; a wrapped label is >= 42.
        final labelSize = tester.getSize(find.text('Theme'));
        expect(
          labelSize.height,
          lessThan(2 * 14 * 1.5),
          reason: 'the label must not degrade to per-character wrap when the '
              'trailing value string claims the content band',
        );
        final label = tester.renderObject<RenderParagraph>(find.text('Theme'));
        expect(label.didExceedMaxLines, isFalse);
      },
    );

    testWidgets(
      'Profile Display Theme tile stays overflow-free at 1.5x in Arabic '
      '(#1076)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await pumpRihlaApp(
          tester,
          scaledTo15x(const Scaffold(body: ProfileDisplaySection())),
          locale: const Locale('ar'),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'the Theme tile row must not overflow at 1.5x under RTL',
        );

        final labelSize = tester.getSize(find.text('المظهر'));
        expect(labelSize.height, lessThan(2 * 14 * 1.5));
      },
    );

    testWidgets(
      'SectionHeader title does not ellipsize when free width remains (#1076)',
      (tester) async {
        tester.view.physicalSize = const Size(700, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await pumpRihlaApp(
          tester,
          scaledTo15x(
            const Scaffold(
              body: SectionHeader(
                title: 'Active journeys',
                actionLabel: 'View history',
              ),
            ),
          ),
        );

        final title = tester.renderObject<RenderParagraph>(
          find.text('ACTIVE JOURNEYS'),
        );
        expect(
          title.didExceedMaxLines,
          isFalse,
          reason: 'the tight Flexible title must absorb ALL free width — '
              'ellipsizing while blank space remains means the free width is '
              'being split with a redundant Spacer',
        );

        final actionRect = tester.getRect(find.text('View history'));
        expect(
          actionRect.right,
          closeTo(700 - 20, 1.0),
          reason: 'the action stays end-aligned without the Spacer',
        );
      },
    );
  });
}
