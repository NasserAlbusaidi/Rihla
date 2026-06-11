// Boot-time surfacing of a RecoveryOutcome marker (#439 C.3).
//
// The marker is the ONLY trace of a swap outcome (the process restarted);
// on the next cold boot it must become a user-visible message + the
// authoritative Sentry signal, exactly once.

import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/auth_error_humanizer.dart';
import 'package:safar/features/auth/services/recovery_outcome.dart';
import 'package:safar/features/auth/services/recovery_outcome_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late List<(String, bool)> snacks;
  late List<String> captures;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    snacks = [];
    captures = [];
  });

  void run({String? Function()? currentUid}) => surfaceRecoveryOutcome(
        prefs: prefs,
        currentUid: currentUid ?? () => null,
        showSnack: (message, {bool isError = false}) =>
            snacks.add((message, isError)),
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

    run();

    expect(snacks, [
      (humanizeAuthErrorCode('invalid-action-code'), true),
    ]);
    expect(captures, ['recovery_failed op=recover code=invalid-action-code']);
    expect(prefs.containsKey(RecoveryOutcome.prefsKey), isFalse);
  });

  test('capture string carries no PII beyond op+code', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: false,
      code: 'user-disabled',
    );

    run();

    expect(captures.single, 'recovery_failed op=google code=user-disabled');
  });

  test('successful restore → success snack, NO capture', () async {
    await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opGoogle, ok: true);

    run();

    expect(snacks, [('Account restored.', false)]);
    expect(captures, isEmpty);
  });

  test('successful email restore → success snack', () async {
    await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opRecover, ok: true);

    run();

    expect(snacks, hasLength(1));
    expect(snacks.single.$2, isFalse);
  });

  test('successful sign-out → silent (no snack, no capture)', () async {
    await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opSignOut, ok: true);

    run();

    expect(snacks, isEmpty);
    expect(captures, isEmpty);
  });

  test('failed sign-out still surfaces', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opSignOut,
      ok: false,
      code: 'network-request-failed',
    );

    run();

    expect(snacks, hasLength(1));
    expect(snacks.single.$2, isTrue);
    expect(captures, hasLength(1));
  });

  test('#458: success marker whose swap did NOT survive → failure notice',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    run(currentUid: () => 'stale-anon-uid');

    expect(snacks, [
      ("Account restore didn't complete. Please try again.", true),
    ]);
    expect(captures, ['recovery_swap_not_durable op=google']);
  });

  test('#458: success marker whose swap survived → success notice', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opRecover,
      ok: true,
      expectedUid: 'durable-uid',
    );

    run(currentUid: () => 'durable-uid');

    expect(snacks, [('Account restored.', false)]);
    expect(captures, isEmpty);
  });

  test('#458: no signed-in user at boot counts as a mismatch', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    run(currentUid: () => null);

    expect(snacks.single.$2, isTrue);
    expect(captures, ['recovery_swap_not_durable op=google']);
  });

  test('#458: unreadable auth (throws) → trust the claim, never false-alarm',
      () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    run(currentUid: () => throw StateError('[core/no-app]'));

    expect(snacks, [('Account restored.', false)]);
    expect(captures, isEmpty);
  });

  test('#458: mismatch capture carries no UID', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opGoogle,
      ok: true,
      expectedUid: 'durable-uid',
    );

    run(currentUid: () => 'stale-anon-uid');

    expect(captures.single, isNot(contains('durable-uid')));
    expect(captures.single, isNot(contains('stale-anon-uid')));
  });

  test('one-shot: a second boot surfaces nothing', () async {
    await writeRecoveryOutcome(
      prefs,
      op: RecoveryOutcome.opRecover,
      ok: false,
      code: 'invalid-action-code',
    );

    run();
    snacks.clear();
    captures.clear();
    run();

    expect(snacks, isEmpty);
    expect(captures, isEmpty);
  });

  test('no marker → nothing', () {
    run();
    expect(snacks, isEmpty);
    expect(captures, isEmpty);
  });

  test('humanizeAuthErrorCode keeps the bootstrap mapping', () {
    expect(
      humanizeAuthErrorCode('invalid-action-code'),
      'This link has expired or was already used. Send a new one.',
    );
    expect(
      humanizeAuthErrorCode('network-request-failed'),
      "No connection. Try again when you're online.",
    );
    expect(humanizeAuthErrorCode('weird-code'), contains('weird-code'));
  });
}
