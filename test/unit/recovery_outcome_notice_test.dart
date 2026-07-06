// Boot-time surfacing of a RecoveryOutcome marker (#439 C.3 / #839).
//
// The marker is the ONLY trace of a swap outcome (the process restarted);
// on the next cold boot it must become a user-visible message + the
// authoritative Sentry signal, exactly once. #839 adds a data-presence probe
// so a wrong/never-linked restore that lands on a genuinely empty account
// gets an honest "no groups yet" instead of a confident "Account restored."

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/app_messenger.dart';
import 'package:safar/features/auth/providers/recovery_outcome_notice_provider.dart';
import 'package:safar/features/auth/services/auth_error_humanizer.dart';
import 'package:safar/features/auth/services/recovery_outcome.dart';
import 'package:safar/features/auth/services/recovery_outcome_notice.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Generic test fixture — deliberately distinct from any real ARB copy so a
/// test failure clearly names which branch fired. Real localization
/// (context → AppLocalizations, EN fallback) is the provider's job and is
/// covered separately by the widget-level AR test below.
const _messages = (
  restoredOk: 'ok-msg',
  restoredEmpty: 'empty-msg',
  swapIncomplete: 'incomplete-msg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late List<(String, bool, Duration)> snacks;
  late List<String> captures;
  late List<String> probedUids;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    snacks = [];
    captures = [];
    probedUids = [];
  });

  Future<void> run({
    String? Function()? currentUid,
    Future<bool?> Function(String uid)? hasData,
  }) => surfaceRecoveryOutcome(
    prefs: prefs,
    currentUid: currentUid ?? () => null,
    hasData:
        hasData ??
        (uid) async {
          probedUids.add(uid);
          return null;
        },
    messages: _messages,
    showSnack:
        (
          message, {
          bool isError = false,
          Duration duration = const Duration(seconds: 4),
        }) => snacks.add((message, isError, duration)),
    capture: captures.add,
  );

  test('failure marker → humanized error snack + Sentry capture + cleared',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opRecover,
      ok: false,
      code: 'invalid-action-code',
    );

    await run();

    expect(snacks, [
      (humanizeAuthErrorCode('invalid-action-code'), true, const Duration(seconds: 4)),
    ]);
    expect(captures, ['recovery_failed op=recover code=invalid-action-code']);
    expect(prefs.containsKey(RecoveryOutcome.prefsKey), isFalse);
    expect(probedUids, isEmpty);
  });

  test('capture string carries no PII beyond op+code', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: false,
      code: 'user-disabled',
    );

    await run();

    expect(captures.single, 'recovery_failed op=google code=user-disabled');
  });

  test('successful sign-out → silent (no snack, no capture)', () async {
    await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opSignOut, ok: true);

    await run();

    expect(snacks, isEmpty);
    expect(captures, isEmpty);
    expect(probedUids, isEmpty);
  });

  test('failed sign-out still surfaces', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opSignOut,
      ok: false,
      code: 'network-request-failed',
    );

    await run();

    expect(snacks, hasLength(1));
    expect(snacks.single.$2, isTrue);
    expect(captures, hasLength(1));
  });

  // ---------------------------------------------------------------------
  // #458 mismatch branch — unchanged, evaluated FIRST, never reaches the
  // #839 probe.
  // ---------------------------------------------------------------------

  test('mismatch → incomplete-msg (swap did NOT survive the restart)',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(currentUid: () => 'stale-anon-uid');

    expect(snacks, [
      (_messages.swapIncomplete, true, const Duration(seconds: 4)),
    ]);
    expect(captures, ['recovery_swap_not_durable op=google']);
    expect(probedUids, isEmpty);
  });

  test('mismatch: no signed-in user at boot counts as a mismatch', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(currentUid: () => null);

    expect(snacks.single.$2, isTrue);
    expect(captures, ['recovery_swap_not_durable op=google']);
    expect(probedUids, isEmpty);
  });

  test('mismatch capture carries no UID', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(currentUid: () => 'stale-anon-uid');

    expect(captures.single, isNot(contains('durable-uid')));
    expect(captures.single, isNot(contains('stale-anon-uid')));
  });

  // ---------------------------------------------------------------------
  // #839 probe branches — only reached once the swap is confirmed durable
  // (or was never checkable).
  // ---------------------------------------------------------------------

  test('restored + hasData(true) → ok', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opRecover,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(
      currentUid: () => 'durable-uid',
      hasData: (uid) async {
        probedUids.add(uid);
        return true;
      },
    );

    expect(snacks, [
      (_messages.restoredOk, false, const Duration(seconds: 4)),
    ]);
    expect(captures, isEmpty);
    expect(probedUids, ['durable-uid']);
  });

  test('restored + confirmed-empty → empty-msg, 8s duration, not an error',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(
      currentUid: () => 'durable-uid',
      hasData: (uid) async {
        probedUids.add(uid);
        return false;
      },
    );

    expect(snacks, [
      (_messages.restoredEmpty, false, const Duration(seconds: 8)),
    ]);
    expect(captures, isEmpty);
    expect(probedUids, ['durable-uid']);
  });

  test('restored + inconclusive probe (null) → ok, never scare', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(
      currentUid: () => 'durable-uid',
      hasData: (uid) async {
        probedUids.add(uid);
        return null;
      },
    );

    expect(snacks, [
      (_messages.restoredOk, false, const Duration(seconds: 4)),
    ]);
    expect(captures, isEmpty);
    expect(probedUids, ['durable-uid']);
  });

  test(
      'uid-throws → ok without probe (unreadable auth trusts the claim, '
      'never false-alarms)', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(currentUid: () => throw StateError('[core/no-app]'));

    expect(snacks, [
      (_messages.restoredOk, false, const Duration(seconds: 4)),
    ]);
    expect(captures, isEmpty);
    expect(probedUids, isEmpty);
  });

  test('expectedUid == null → probe targets currentUid()', () async {
    // Legacy v1 marker (or any success marker written without an
    // expectedUid): the mismatch check is skipped entirely, so #839 must
    // still probe against whoever is ACTUALLY signed in, per Gate r1.
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
    );

    await run(
      currentUid: () => 'uid-current',
      hasData: (uid) async {
        probedUids.add(uid);
        return false;
      },
    );

    expect(probedUids, ['uid-current']);
    expect(snacks, [
      (_messages.restoredEmpty, false, const Duration(seconds: 8)),
    ]);
  });

  test('expectedUid == null and no current uid → trusts the claim (nothing '
      'to probe)', () async {
    await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opGoogle, ok: true);

    await run(currentUid: () => null);

    expect(snacks, [
      (_messages.restoredOk, false, const Duration(seconds: 4)),
    ]);
    expect(captures, isEmpty);
    expect(probedUids, isEmpty);
  });

  // ---------------------------------------------------------------------
  // #990 breadcrumb: ONLY the VERIFIED restore-success arm (expectedUid
  // recorded AND matching the current uid) writes `recovery_name_seed_uid`;
  // every other arm leaves it absent. The deviceName self-heal is scoped to
  // this breadcrumb — a false write here would reopen the #293 shadow-claim
  // promotion the Gate killed twice.
  // ---------------------------------------------------------------------

  const seedKey = 'recovery_name_seed_uid';

  test('#990: verified google restore writes the seed breadcrumb — before '
      'the async probe runs', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    String? breadcrumbAtProbe;
    await run(
      currentUid: () => 'durable-uid',
      hasData: (uid) async {
        breadcrumbAtProbe = prefs.getString(seedKey);
        return true;
      },
    );

    expect(prefs.getString(seedKey), 'durable-uid');
    expect(
      breadcrumbAtProbe,
      'durable-uid',
      reason: 'the breadcrumb must land before the probe — the probe only '
          'picks snack copy and must not gate the heal',
    );
  });

  test('#990: verified email-link restore writes the seed breadcrumb',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opRecover,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(currentUid: () => 'durable-uid');

    expect(prefs.getString(seedKey), 'durable-uid');
  });

  test('#990: failure marker does NOT write the breadcrumb', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: false,
      code: 'user-disabled',
    );

    await run(currentUid: () => 'whoever');

    expect(prefs.containsKey(seedKey), isFalse);
  });

  test('#990: uid mismatch (swap not durable) does NOT write the breadcrumb',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(currentUid: () => 'stale-anon-uid');

    expect(prefs.containsKey(seedKey), isFalse);
  });

  test('#990: sign-out does NOT write the breadcrumb', () async {
    await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opSignOut, ok: true);

    await run(currentUid: () => 'whoever');

    expect(prefs.containsKey(seedKey), isFalse);
  });

  test('#990: legacy marker without expectedUid (unverifiable) does NOT '
      'write the breadcrumb', () async {
    await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opGoogle, ok: true);

    await run(currentUid: () => 'uid-current');

    expect(prefs.containsKey(seedKey), isFalse);
  });

  test('#990: unreadable auth (uid throws) does NOT write the breadcrumb',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    await run(currentUid: () => throw StateError('[core/no-app]'));

    expect(prefs.containsKey(seedKey), isFalse);
  });

  test('one-shot: a second boot surfaces nothing', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opRecover,
      ok: false,
      code: 'invalid-action-code',
    );

    await run();
    snacks.clear();
    captures.clear();
    await run();

    expect(snacks, isEmpty);
    expect(captures, isEmpty);
  });

  test('no marker → nothing', () async {
    await run();
    expect(snacks, isEmpty);
    expect(captures, isEmpty);
  });

  test(
    'humanizeAuthErrorCode: EN-literal fallback when no l10n is supplied',
    () {
      // surfaceRecoveryOutcome (recovery_outcome_notice.dart) calls this with
      // no l10n on purpose — it stays context-free (#839) — so this fallback
      // contract must hold regardless of the #841 PR-3 localized branch below.
      expect(
        humanizeAuthErrorCode('invalid-action-code'),
        'This link has expired or was already used. Send a new one.',
      );
      expect(
        humanizeAuthErrorCode('network-request-failed'),
        "No connection. Try again when you're online.",
      );
      expect(humanizeAuthErrorCode('weird-code'), contains('weird-code'));
    },
  );

  test(
    'humanizeAuthErrorCode: localizes when l10n is supplied (#841 PR-3)',
    () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));

      expect(
        humanizeAuthErrorCode('invalid-action-code', l10n: en),
        en.authEmailLinkErrorExpired,
      );
      expect(
        humanizeAuthErrorCode('invalid-action-code', l10n: ar),
        ar.authEmailLinkErrorExpired,
      );
      expect(
        humanizeAuthErrorCode('weird-code', l10n: en),
        en.authEmailLinkErrorGeneric('weird-code'),
      );
    },
  );

  // ---------------------------------------------------------------------
  // Gate r1: widget-level l10n test. The provider's own
  // `appMessengerKey.currentContext → AppLocalizations.of(ctx)` resolution
  // is otherwise untested, and its EN-literal fallback would silently mask
  // total localization failure for AR users — so this drives the REAL
  // provider (not the pure function) through a real MaterialApp.
  // ---------------------------------------------------------------------

  testWidgets(
      'AR l10n: provider resolves and shows the localized '
      'recoveryRestoredEmpty string', (tester) async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'uid-1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          recoveryOutcomeCurrentUidProvider.overrideWithValue(() => 'uid-1'),
          recoveryOutcomeProbeProvider.overrideWithValue(
            (_) async => false,
          ),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: appMessengerKey,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(recoveryOutcomeNoticeProvider);
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );

    // First frame commits the postFrameCallback; a couple more pumps let the
    // async probe resolve and the SnackBar's entrance animation begin.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(find.text(ar.recoveryRestoredEmpty), findsOneWidget);
  });
}
