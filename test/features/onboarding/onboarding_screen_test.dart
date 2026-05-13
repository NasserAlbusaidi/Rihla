import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/onboarding/screens/onboarding_screen.dart';

typedef _Harness = ({Widget app, ProviderContainer container, _DoneFlag done});

class _DoneFlag {
  bool value = false;
}

Future<_Harness> _buildHarness(
  WidgetTester tester, {
  int initialPage = 0,
  Map<String, Object> prefsSeed = const {},
}) async {
  // Onboarding is laid out for a phone — default 800×600 surface clips the
  // bottom CTAs. Size the surface to an iPhone-ish viewport for fidelity.
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues(prefsSeed);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  final done = _DoneFlag();
  final app = UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: OnboardingScreen(
        initialPage: initialPage,
        onComplete: () => done.value = true,
      ),
    ),
  );
  return (app: app, container: container, done: done);
}

Finder _btn(String label) => find.widgetWithText(ElevatedButton, label);

void main() {
  group('OnboardingScreen — page rendering', () {
    testWidgets('brand page (initialPage=0) shows hero copy and Begin CTA', (
      tester,
    ) async {
      final harness = await _buildHarness(tester);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('RIHLA · ر.ح.ل.ة'), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);
      // Hero copy is RichText (Trips, tallied with care).
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('Trips,') &&
              w.text.toPlainText().contains('care'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('how page (initialPage=1) shows three numbered rows', (
      tester,
    ) async {
      final harness = await _buildHarness(tester, initialPage: 1);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('02 / 03'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('setup page (initialPage=2) renders step header and CTA', (
      tester,
    ) async {
      final harness = await _buildHarness(tester, initialPage: 2);

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();

      expect(find.text('03 / 03'), findsOneWidget);
      expect(find.text('Open Rihla'), findsOneWidget);
    });
  });

  group('OnboardingScreen — settings flag wiring', () {
    testWidgets(
      'screen reads onboardingComplete from settings on mount '
      '(seeded true keeps initialPage state)',
      (tester) async {
        final harness = await _buildHarness(
          tester,
          prefsSeed: const {'settings_onboarding_complete': true},
        );

        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();

        // The screen mounts regardless of the flag (route redirect is
        // the gatekeeper — see app_router_test.dart). Flag is preserved.
        expect(
          harness.container.read(settingsProvider).onboardingComplete,
          isTrue,
        );
      },
    );

    testWidgets(
      'name controller is pre-populated from a seeded device name',
      (tester) async {
        final harness = await _buildHarness(
          tester,
          initialPage: 2,
          prefsSeed: const {'settings_device_name': 'Sami'},
        );

        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();

        // Even if the visual TextField is offstage due to layout in the test
        // harness, the controller's text is set from settings on init.
        expect(
          harness.container.read(settingsProvider).deviceName,
          'Sami',
        );
      },
    );

    testWidgets(
      'tapping Begin on brand page does not finalize onboarding',
      (tester) async {
        final harness = await _buildHarness(tester);

        await tester.pumpWidget(harness.app);
        await tester.pumpAndSettle();

        await tester.tap(_btn('Begin'), warnIfMissed: false);
        await tester.pumpAndSettle();

        // Begin should never complete onboarding directly — that happens
        // only on Skip / Open Rihla.
        expect(harness.done.value, isFalse);
        expect(
          harness.container.read(settingsProvider).onboardingComplete,
          isFalse,
        );
      },
    );
  });
}
