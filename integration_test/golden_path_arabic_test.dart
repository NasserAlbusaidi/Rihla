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

import 'dart:convert' show jsonEncode;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:safar/core/services/settings_service.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
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

  testWidgets('cold boot in ar → home → create group → ledger', (tester) async {
    final ar = AppLocalizationsAr();
    _log('--- TEST START (locale=ar) ---');
    app.main();

    // The empty-onboarding branch from golden_path_test.dart:33-77 applies
    // identically here — if onboarding is dead code today, we land on home
    // directly; if it's re-wired, we walk through the localized Arabic copy.
    await _waitFor(
      tester,
      label: 'onboarding-or-home',
      predicate: () =>
          find.text(ar.onboardingBegin).evaluate().isNotEmpty ||
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 90),
    );

    if (find.byKey(const Key('home_screen')).evaluate().isEmpty) {
      // Onboarding path — copy the 3-tap walk from golden_path_test.dart.
      await tester.tap(find.text(ar.onboardingBegin).first);
      await _settle(tester);
      await _waitFor(
        tester,
        label: 'onboarding-p2',
        predicate: () => find.text(ar.onboardingNext).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(ar.onboardingNext).first);
      await _settle(tester);
      await _waitFor(
        tester,
        label: 'onboarding-p3',
        predicate: () =>
            find.text(ar.onboardingOpenRihla).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(ar.onboardingOpenRihla).first);
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
      reason:
          'WordmarkLogo did not swap to Arabic glyph on home — '
          'locale chain (settings.languageCode -> localeProvider -> '
          'MaterialApp.locale) is broken',
    );
    expect(
      find.text('Rihla'),
      findsNothing,
      reason:
          'English wordmark still visible after Arabic boot — '
          'WordmarkLogo locale branch did not flip',
    );

    expect(find.text(ar.homeBottomNavGroups), findsWidgets);
    expect(find.text(ar.homeBottomNavActivity), findsWidgets);
    expect(find.text(ar.homeBottomNavProfile), findsWidgets);

    final activityTab = find.byKey(HomeKeys.bottomNavActivity);
    expect(
      activityTab,
      findsOneWidget,
      reason: 'home_bottom_nav_activity missing on Home after skeleton clear',
    );
    await tester.tap(activityTab);
    await _settle(tester);
    expect(
      find.text(ar.activityTitle),
      findsWidgets,
      reason: 'Activity tab did not render Arabic title copy.',
    );

    // PR2a Profile-translation assertion (codex round 1 P1-A): jump to the
    // Profile tab and assert one of its translated section labels renders in
    // Arabic. This proves the full chain end-to-end — locale wiring, ARB key
    // resolution, and the actual widget consuming context.l10n.
    final profileTab = find.byKey(HomeKeys.bottomNavProfile);
    expect(
      profileTab,
      findsOneWidget,
      reason:
          'home_bottom_nav_profile missing on Home after skeleton clear (ar)',
    );
    await tester.tap(profileTab);
    await _settle(tester);

    expect(
      find.text(ar.profileSectionPreferences),
      findsOneWidget,
      reason:
          'Profile screen "Preferences" section not translated to ar — '
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

    // #441: the durable-credential gate blocks an anonymous create. Link a
    // fake Google credential first (Auth emulator accepts a JSON idToken) —
    // mirrors golden_path_test.dart.
    final gateUser = FirebaseAuth.instance.currentUser;
    expect(gateUser, isNotNull, reason: 'anon session missing before gate link');
    if (gateUser!.isAnonymous) {
      await gateUser.linkWithCredential(
        GoogleAuthProvider.credential(
          idToken: jsonEncode({
            'sub': 'golden-path-ar-google-sub',
            'email': 'golden-ar@example.com',
            'email_verified': true,
          }),
        ),
      );
    }

    final fab = find.byKey(const Key('home_create_group_fab'));
    expect(
      fab,
      findsOneWidget,
      reason: 'home_create_group_fab missing after skeleton clear (ar)',
    );
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
      predicate: () => find.byKey(GroupKeys.createScreen).evaluate().isNotEmpty,
    );
    _log('CHECKPOINT: create-group screen open (ar)');
    expect(find.text(ar.groupNew), findsOneWidget);

    await tester.enterText(
      find.byKey(GroupKeys.groupNameInput),
      'QA Arabic Smoke Group',
    );
    await _settle(tester);

    await tester.enterText(
      find.byKey(GroupKeys.deviceNameInput),
      'QA Arabic Bot',
    );
    await _settle(tester);

    _log('CHECKPOINT: submitting create-group form (ar)');
    await tester.tap(find.byKey(GroupKeys.createGroupButton));
    await _settle(tester, timeout: const Duration(seconds: 20));

    await _waitFor(
      tester,
      label: 'post-create share prompt or group detail',
      predicate: () =>
          find.text(ar.commonDone).evaluate().isNotEmpty ||
          find.byKey(GroupKeys.detailScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );

    if (find.byKey(GroupKeys.detailScreen).evaluate().isEmpty) {
      _log('CHECKPOINT: dismissing share prompt (ar)');
      await tester.tap(find.text(ar.commonDone).last);
      await _settle(tester, timeout: const Duration(seconds: 12));
    }

    await _waitFor(
      tester,
      label: 'group_detail_screen',
      predicate: () => find.byKey(GroupKeys.detailScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    _log('CHECKPOINT: group detail rendered after create (ar)');

    await _waitFor(
      tester,
      label: 'new-event action',
      predicate: () =>
          find.text(ar.eventNew).evaluate().isNotEmpty ||
          find.text(ar.groupCreateEvent).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    final newEventAction = find.text(ar.eventNew);
    if (newEventAction.evaluate().isNotEmpty) {
      await tester.ensureVisible(newEventAction.first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(newEventAction.first);
    } else {
      final createEventAction = find.text(ar.groupCreateEvent).first;
      await tester.ensureVisible(createEventAction);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(createEventAction);
    }
    await _settle(tester, timeout: const Duration(seconds: 12));

    await _waitFor(
      tester,
      label: 'event_type_picker_screen',
      predicate: () =>
          find.byKey(EventKeys.eventTypePickerScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    _log('CHECKPOINT: event type picker open (ar)');
    expect(find.text(ar.eventPickerTitle), findsOneWidget);

    final eventContinueButton = find.byKey(EventKeys.createEventButton);
    await tester.ensureVisible(eventContinueButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(eventContinueButton);
    await _settle(tester, timeout: const Duration(seconds: 12));

    await _waitFor(
      tester,
      label: 'create_event_screen',
      predicate: () =>
          find.byKey(EventKeys.createEventScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    _log('CHECKPOINT: create-event screen open (ar)');
    expect(find.text(ar.eventCreate), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'QA Arabic Smoke Event',
    );
    await _settle(tester);

    final submitEventButton = find.byKey(EventKeys.createEventButton);
    await tester.ensureVisible(submitEventButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(submitEventButton);
    await _settle(tester, timeout: const Duration(seconds: 20));

    await _waitFor(
      tester,
      label: 'event hub or ledger',
      predicate: () =>
          find.byKey(EventKeys.screen).evaluate().isNotEmpty ||
          find.byKey(LedgerKeys.screen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );

    if (find.byKey(LedgerKeys.screen).evaluate().isEmpty) {
      _log('CHECKPOINT: opening ledger from event hub (ar)');
      if (find.byKey(EventKeys.ledgerCard).evaluate().isEmpty) {
        _log('CHECKPOINT: empty hub has no ledger card; adding first expense');
        final addExpenseChip = find.byKey(EventKeys.addExpenseChip);
        await tester.ensureVisible(addExpenseChip);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(addExpenseChip);
        await _settle(tester, timeout: const Duration(seconds: 12));

        await _waitFor(
          tester,
          label: 'ledger_add_expense_screen',
          predicate: () =>
              find.byKey(LedgerKeys.addExpenseScreen).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
        );

        await tester.enterText(find.byType(TextField).first, '12.345');
        await _settle(tester);

        final addAction = find.widgetWithText(FilledButton, ar.editorActionAdd);
        expect(
          addAction,
          findsOneWidget,
          reason: 'Add expense action did not render in Arabic.',
        );
        await tester.tap(addAction);
        await _settle(tester, timeout: const Duration(seconds: 20));

        await _waitFor(
          tester,
          label: 'expense success dialog',
          predicate: () => find.text(ar.commonDone).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
        );
        await tester.tap(find.widgetWithText(ElevatedButton, ar.commonDone));
        await _settle(tester, timeout: const Duration(seconds: 12));

        await _waitFor(
          tester,
          label: 'event hub ledger summary',
          predicate: () =>
              find.byKey(EventKeys.ledgerCard).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
        );
      }

      final ledgerCard = find.byKey(EventKeys.ledgerCard);
      await tester.ensureVisible(ledgerCard);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(ledgerCard);
      await _settle(tester, timeout: const Duration(seconds: 12));
    }

    await _waitFor(
      tester,
      label: 'ledger_screen',
      predicate: () => find.byKey(LedgerKeys.screen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    _log('CHECKPOINT: ledger rendered (ar)');

    await _waitFor(
      tester,
      label: 'arabic ledger copy',
      predicate: () =>
          find.text(ar.ledgerAddExpense).evaluate().isNotEmpty ||
          find.text(ar.ledgerEmptyStateTitle).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    expect(
      find.text(ar.ledgerAddExpense),
      findsOneWidget,
      reason:
          'Ledger sticky CTA did not render the Arabic ledgerAddExpense key.',
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
