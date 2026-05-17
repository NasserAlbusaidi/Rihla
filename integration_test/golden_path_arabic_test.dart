// integration_test/golden_path_arabic_test.dart
//
// Mirror of golden_path_test.dart but boots the app in Arabic locale by
// pre-seeding SharedPreferences. Catches RTL render exceptions, missing
// ARB key fallbacks, and broken transition layouts in ar. PR2a unlocked
// the user-facing toggle and translated Settings/Profile, so this test
// now also asserts that the Profile tab renders Arabic content.
//
// Run with:
//   firebase emulators:start --only auth,firestore,functions  # other terminal
//   flutter test integration_test/golden_path_arabic_test.dart \
//     -d <ios-sim-id> \
//     --dart-define-from-file=config.test.json

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:safar/core/services/settings_service.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Seed via the SAME constant SettingsService.loadSettings reads.
    // Hard-coding 'settings_language' here would silently regress if the
    // constant is ever renamed (which is exactly the bug this seed-key
    // import prevents — see PR description's "code-verification corrections"
    // note).
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.languageKey: 'ar',
    });
  });

  testWidgets('cold boot in ar → home → create group (no exceptions)',
      (tester) async {
    _log('--- TEST START (locale=ar) ---');
    app.main();

    // The empty-onboarding branch from golden_path_test.dart:33-77 applies
    // identically here — if onboarding is dead code today, we land on home
    // directly; if it's re-wired, we walk through it. The labels are still
    // English in PR1 because Settings/Onboarding aren't translated yet
    // (per PR1 non-goals); PR3 makes onboarding strings ARB-driven.
    await _waitFor(
      tester,
      label: 'onboarding-or-home',
      predicate: () =>
          find.text('Begin').evaluate().isNotEmpty ||
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 90),
    );

    if (find.byKey(const Key('home_screen')).evaluate().isEmpty) {
      // Onboarding path — copy the 3-tap walk from golden_path_test.dart.
      await tester.tap(find.text('Begin').first);
      await _settle(tester);
      await _waitFor(
        tester,
        label: 'onboarding-p2',
        predicate: () => find.text('Next').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Next').first);
      await _settle(tester);
      await _waitFor(
        tester,
        label: 'onboarding-p3',
        predicate: () => find.text('Open Rihla').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Open Rihla').first);
      await _settle(tester);
    }

    await _waitFor(
      tester,
      label: 'home_screen',
      predicate: () =>
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty,
    );
    _log('CHECKPOINT: home rendered (ar)');

    // Same Skeletonizer drain pattern as golden_path_test.dart:91-96.
    await _waitFor(
      tester,
      label: 'skeleton cleared',
      predicate: () => find.byType(Skeletonizer).evaluate().isEmpty,
      timeout: const Duration(seconds: 30),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    // Positive locale signal (codex round 1 [P1]) — proves the full chain:
    //   SharedPreferences.languageCode='ar' -> settingsProvider -> localeProvider
    //   -> MaterialApp.router(locale='ar') -> Localizations.localeOf
    //   -> WordmarkLogo Arabic branch.
    // Without this assertion the test passes whether locale wiring works or
    // not. WordmarkLogo is rendered on the home screen.
    expect(
      find.text('رحلة'),
      findsOneWidget,
      reason: 'WordmarkLogo did not swap to Arabic glyph on home — '
          'locale chain (settings.languageCode -> localeProvider -> '
          'MaterialApp.locale) is broken',
    );
    expect(
      find.text('Rihla'),
      findsNothing,
      reason: 'English wordmark still visible after Arabic boot — '
          'WordmarkLogo locale branch did not flip',
    );

    // PR2a Profile-translation assertion (codex round 1 P1-A): jump to the
    // Profile tab and assert one of its translated section labels renders in
    // Arabic. This proves the full chain end-to-end — locale wiring, ARB key
    // resolution, and the actual widget consuming context.l10n.
    final profileTab = find.byKey(HomeKeys.bottomNavProfile);
    expect(
      profileTab,
      findsOneWidget,
      reason: 'home_bottom_nav_profile missing on Home after skeleton clear (ar)',
    );
    await tester.tap(profileTab);
    await _settle(tester);

    expect(
      find.text('التفضيلات'),
      findsOneWidget,
      reason: 'Profile screen "Preferences" section not translated to ar — '
          'check localeProvider chain + ARB key profileSectionPreferences',
    );

    // Return to the Groups tab (the default landing surface) for the rest
    // of the smoke test — the create-group FAB lives there.
    final groupsTab = find.byKey(HomeKeys.bottomNavGroups);
    expect(
      groupsTab,
      findsOneWidget,
      reason: 'home_bottom_nav_groups missing after Profile detour (ar)',
    );
    await tester.tap(groupsTab);
    await _settle(tester);

    final fab = find.byKey(const Key('home_create_group_fab'));
    expect(fab, findsOneWidget,
        reason: 'home_create_group_fab missing after skeleton clear (ar)');
    await tester.ensureVisible(fab);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(fab);
    await _settle(tester);

    // Mirror chooser-sheet branch from golden_path_test.dart:117-123 — the
    // empty-state path pops a "create vs join" chooser before the form.
    final createOption = find.byKey(const Key('home_create_group_option'));
    if (createOption.evaluate().isNotEmpty) {
      _log('CHECKPOINT: tapping create-group option in chooser sheet (ar)');
      await tester.tap(createOption);
      await _settle(tester);
    }

    // Real key from lib/features/groups/keys/group_keys.dart —
    // GroupKeys.createScreen = Key('group_create_screen').
    await _waitFor(
      tester,
      label: 'group_create_screen',
      predicate: () =>
          find.byKey(const Key('group_create_screen')).evaluate().isNotEmpty,
    );

    _log('--- TEST PASSED (locale=ar) ---');
  });
}

// _waitFor / _settle / _log mirror the existing helpers in
// integration_test/golden_path_test.dart:159-209. Cross-test refactor into
// integration_test/_helpers.dart is deferred — out of scope for PR1.

Future<void> _waitFor(
  WidgetTester tester, {
  required String label,
  required bool Function() predicate,
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await tester.pump(interval);
  }
  fail('Timeout (${timeout.inSeconds}s) waiting for: $label');
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
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void _log(String msg) {
  // ignore: avoid_print
  print('[golden_path_ar] $msg');
}
