// Integration test: drives the real app on a real device against the Firebase
// emulator suite. Boots cold, walks onboarding, lands on home, creates a group.
//
// Run with:
//   firebase emulators:start --only auth,firestore,functions   # in another terminal
//   flutter test integration_test/golden_path_test.dart \
//     -d <ios-sim-id> \
//     --dart-define-from-file=config.test.json
//
// Failure here = real signal: cold-boot regression, plugin breakage on iOS,
// or a routing/widget-key drift. Each checkpoint is logged so log scrubbers
// can reconstruct where the run stalled.

import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:safar/main.dart' as app;

late IntegrationTestWidgetsFlutterBinding _binding;

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('cold boot → onboarding → home → create group', (tester) async {
    _log('--- TEST START ---');
    app.main();

    await _waitFor(
      tester,
      label: 'onboarding-or-home',
      predicate: () =>
          find.text('Begin').evaluate().isNotEmpty ||
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 90),
    );
    await _shot('01-cold-boot');

    if (find.byKey(const Key('home_screen')).evaluate().isNotEmpty) {
      // OnboardingScreen is currently dead code — not mounted by the router or
      // any gate widget. Cold boot lands straight on home. Kept in the test in
      // case onboarding is re-wired later.
      _log('Landed on home directly (no onboarding mount).');
    } else {
      await _shot('02-onboarding-p1');
      _log('CHECKPOINT: onboarding page 1 — tapping Begin');
      await tester.tap(find.text('Begin').first);
      await _settle(tester);

      await _waitFor(
        tester,
        label: 'onboarding-p2 "Next"',
        predicate: () => find.text('Next').evaluate().isNotEmpty,
      );
      await _shot('03-onboarding-p2');
      _log('CHECKPOINT: onboarding page 2 — tapping Next');
      await tester.tap(find.text('Next').first);
      await _settle(tester);

      await _waitFor(
        tester,
        label: 'onboarding-p3 "Open Rihla"',
        predicate: () => find.text('Open Rihla').evaluate().isNotEmpty,
      );
      await _shot('04-onboarding-p3');
      _log('CHECKPOINT: onboarding page 3 — tapping Open Rihla');
      await tester.tap(find.text('Open Rihla').first);
      await _settle(tester);
    }

    await _waitFor(
      tester,
      label: 'home_screen',
      predicate: () =>
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty,
    );
    _log('CHECKPOINT: home rendered');
    await _shot('05-home');

    // Wait for the loading skeleton (Skeletonizer + IgnorePointer wrapper in
    // _buildSkeleton) to clear before interacting. pumpAndSettle won't help —
    // Firestore streams keep emitting indefinitely.
    await _waitFor(
      tester,
      label: 'home loaded (Skeletonizer cleared)',
      predicate: () => find.byType(Skeletonizer).evaluate().isEmpty,
      timeout: const Duration(seconds: 30),
    );
    _log('CHECKPOINT: skeleton cleared');
    // Drain the entrance animations on the SectionHeader / cards
    // (.animate().fadeIn(delay: 500ms, duration: 400ms)).
    await tester.pump(const Duration(milliseconds: 1500));
    _log('CHECKPOINT: entrance animations settled');
    await _shot('05a-home-loaded');

    final fab = find.byKey(const Key('home_create_group_fab'));
    expect(fab, findsOneWidget,
        reason: 'home_create_group_fab missing after skeleton clear');
    // Whether the loaded path puts the FAB in a SectionHeader scrolled below
    // the fold or the empty path puts it on a visible ElevatedButton, scroll
    // it into view before tapping. ensureVisible scrolls within the nearest
    // Scrollable. No-op when already visible.
    await tester.ensureVisible(fab);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    _log('CHECKPOINT: FAB ensured visible — tapping');
    await tester.tap(fab);
    await _settle(tester);

    // Some entry points pop a chooser sheet first (create vs join).
    final createOption = find.byKey(const Key('home_create_group_option'));
    if (createOption.evaluate().isNotEmpty) {
      _log('CHECKPOINT: tapping create-group option in chooser sheet');
      await tester.tap(createOption);
      await _settle(tester);
    }

    await _waitFor(
      tester,
      label: 'group_create_screen',
      predicate: () =>
          find.byKey(const Key('group_create_screen')).evaluate().isNotEmpty,
    );
    _log('CHECKPOINT: create-group screen open');
    await _shot('06-create-group');

    await tester.enterText(
      find.byKey(const Key('group_name_input')),
      'QA Smoke Group',
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(const Key('group_device_name_input')),
      'QA Bot',
    );
    await _settle(tester);
    await _shot('07-create-group-filled');

    _log('CHECKPOINT: submitting create-group form');
    await tester.tap(find.byKey(const Key('group_create_button')));

    // Firestore write + nav + share-prompt bottom sheet. Give it room.
    await _settle(tester, timeout: const Duration(seconds: 20));
    await _shot('08-post-create-group');
    _log('--- TEST END ---');
  });
}

// ───────────────────────────────────────────── helpers

void _log(String msg) {
  // Picked up by Runner via flutter run console.
  // ignore: avoid_print
  print('[golden_path] $msg');
}

Future<void> _shot(String name) async {
  try {
    if (Platform.isAndroid) {
      await _binding.convertFlutterSurfaceToImage();
    }
    await _binding.takeScreenshot(name);
  } catch (e) {
    _log('takeScreenshot($name) failed: $e');
  }
}

Future<void> _settle(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
  } catch (_) {
    // Live Firestore streams keep emitting; pumpAndSettle will time out.
    // Fall back to a fixed pump so the test keeps moving.
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _waitFor(
  WidgetTester tester, {
  required String label,
  required bool Function() predicate,
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      _log('  ✓ found: $label');
      return;
    }
    await tester.pump(interval);
  }
  fail('Timeout (${timeout.inSeconds}s) waiting for: $label');
}
