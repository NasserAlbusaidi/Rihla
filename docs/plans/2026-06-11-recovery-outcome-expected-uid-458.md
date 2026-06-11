# Recovery Outcome Expected-UID Verification (#458) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the boot-time recovery notice tell the truth: embed the expected post-swap UID in the `RecoveryOutcome` marker and verify it against the live `FirebaseAuth` UID at boot, so a swap that doesn't survive the forced restart surfaces a failure notice instead of a false "Account restored."

**Architecture:** Three-layer change along the existing marker pipeline: (1) `RecoveryOutcome` gains an optional `expectedUid` field (write side: `AuthRecoveryService` success paths for `google`/`recover` ops only); (2) `surfaceRecoveryOutcome` gains an injected `currentUid` callback and downgrades a claimed success to a failure notice when the live UID doesn't match; (3) the notice provider wires `FirebaseConfig.currentUser?.uid`. Sign-out markers and all failure markers are untouched. Legacy markers (no `expectedUid`) keep today's trust-the-claim behavior.

**Tech Stack:** Flutter/Dart, SharedPreferences JSON marker, firebase_auth, flutter_test + mocktail.

**Issue:** Closes #458 (follow-up to #456/#457, hardens the #439 notice).

---

## Context for a zero-context engineer

- The marker is written in `lib/features/auth/services/recovery_outcome.dart` and consumed one-shot on cold boot by `lib/features/auth/services/recovery_outcome_notice.dart`, wired via `lib/features/auth/providers/recovery_outcome_notice_provider.dart` (watched from `appBootstrapProvider`, which `SafarApp.build` watches after the cache-isolation guard — so on cold boot the `ScaffoldMessenger` key is mounted before the post-frame callback fires).
- Write sites (all in `lib/features/auth/services/auth_recovery_service.dart`): `restoreWithGoogle` (`:288` ok=true, `:291` ok=false), `restoreWithEmailLink` (`:355` ok=true, `:362` ok=false), `signOutCurrentDevice` (`:440` ok=true, `:446` ok=false). Only the two restore-success sites change.
- Callsite classification (verification principle 1): `writeRecoveryOutcome` — OUTBOUND, 6 sites, all in `AuthRecoveryService`; `readAndClearRecoveryOutcome` — INBOUND, 1 site (`surfaceRecoveryOutcome`); `surfaceRecoveryOutcome` — INBOUND, 1 site (the provider). No other consumers exist (verified by grep 2026-06-11).
- PII rule nuance: the existing doc comment says the marker never carries a UID. That rule's real target is the **Sentry capture string** (op + code only). Storing the UID in the *local* marker adds no exposure — SharedPreferences already holds the full FirebaseAuth user blob, UID included. The mismatch capture string must NOT contain either UID. Update the doc comment to scope the rule precisely.
- `FirebaseConfig.currentUser` (`lib/core/config/firebase_config.dart:214`) **throws** `[core/no-app]` when Firebase isn't initialized — it does not return null. The read must happen inside a guard (established pattern, see CLAUDE.md gotcha). We therefore inject a `String? Function()` callback and try/catch the call inside `surfaceRecoveryOutcome`; on throw we fall back to legacy trust-the-claim (never alarm on an unverifiable claim).
- `null` from the callback means "no signed-in user" — after `_AuthGate` that should be impossible, so for a marker carrying an `expectedUid` it is a genuine mismatch → failure notice.
- Version field: bump `_version` to 2 (write side documentation only — the reader never gates on `v` and parses fields tolerantly, so legacy v1 markers still parse, with `expectedUid == null`).

## Verification-principles report (run while authoring, 2026-06-11)

1. **Callsites classified** — see Context above; grep re-run this session.
2. **Claims vs code** — `FirebaseConfig.currentUser` exists at `firebase_config.dart:214` and throws without an app (doc + gotcha confirmed); write-site line numbers confirmed by Read; `appMessengerKey` mounts on `MaterialApp.router` (`main.dart:232`).
3. **Read-path per write-path** — new field written by `AuthRecoveryService` restore successes; read by exactly one consumer, `surfaceRecoveryOutcome`. Named and tested.
4. **Fields enumerated from the type** — `RecoveryOutcome { op, ok, code, atMillis }` + new `expectedUid`. JSON keys: `v`, `op`, `ok`, `code`, `atMillis`, + new `expectedUid`.
5. **Data contract spelled out** — marker JSON gains optional string key `expectedUid`; `surfaceRecoveryOutcome` signature gains `required String? Function() currentUid`; capture string for mismatch is exactly `recovery_swap_not_durable op=<op>` (no code, no UIDs).
6. **Arithmetic decomposition** — n/a (no money math).
7. **Orthogonal adversarial axis** — fix is on the success path (axis A); worked examples below exercise sign-out (op axis), legacy markers (time/version axis), and throwing auth reads (environment axis).

---

### Task 1: Marker carries `expectedUid` (shape + writer)

**Files:**
- Modify: `lib/features/auth/services/recovery_outcome.dart`
- Test: `test/unit/recovery_outcome_test.dart`

**Step 1: Write the failing tests**

Append to the existing group in `test/unit/recovery_outcome_test.dart` (read the file first; follow its local helper style):

```dart
test('round-trips expectedUid (#458)', () async {
  await writeRecoveryOutcome(
    prefs,
    op: RecoveryOutcome.opGoogle,
    ok: true,
    expectedUid: 'durable-uid-1',
  );

  final outcome = readAndClearRecoveryOutcome(prefs);

  expect(outcome!.expectedUid, 'durable-uid-1');
});

test('legacy marker without expectedUid reads as null (#458)', () async {
  await writeRecoveryOutcome(prefs, op: RecoveryOutcome.opGoogle, ok: true);

  final outcome = readAndClearRecoveryOutcome(prefs);

  expect(outcome!.ok, isTrue);
  expect(outcome.expectedUid, isNull);
});
```

**Step 2: Run them — expect compile failure (no such parameter/getter)**

Run: `flutter test test/unit/recovery_outcome_test.dart`
Expected: FAIL — `No named parameter with the name 'expectedUid'`.

**Step 3: Implement**

In `recovery_outcome.dart`:
- Add `this.expectedUid` to the constructor and `final String? expectedUid;` to the fields.
- Bump `static const int _version = 1;` → `2`.
- `toJson`: add `'expectedUid': ?expectedUid,`.
- `writeRecoveryOutcome`: add `String? expectedUid` named param, pass through to the constructor.
- `readAndClearRecoveryOutcome`: parse with the existing idiom — `expectedUid: decoded['expectedUid'] as String?,`.
- Update the class doc PII paragraph to:

```dart
/// PII rules: `code` is ONLY a [FirebaseAuthException.code] or an error
/// runtimeType — never a message, email, UID, oobCode, or link. The
/// LOCAL marker may carry `expectedUid` (#458) — prefs already hold the
/// full FirebaseAuth user blob, so this adds no exposure — but no UID may
/// ever reach a Sentry capture string.
```

**Step 4: Run tests — expect pass**

Run: `flutter test test/unit/recovery_outcome_test.dart`
Expected: PASS (all, including pre-existing).

**Step 5: Commit**

```bash
git add lib/features/auth/services/recovery_outcome.dart test/unit/recovery_outcome_test.dart
git commit -m "feat(auth): recovery outcome marker carries expected post-swap UID (Refs #458)"
```

### Task 2: Boot notice verifies the claim (the regression test for the false success)

**Files:**
- Modify: `lib/features/auth/services/recovery_outcome_notice.dart`
- Test: `test/unit/recovery_outcome_notice_test.dart`

**Step 1: Write the failing tests**

Update the `run()` helper to inject the live UID (default keeps legacy tests meaningful):

```dart
void run({String? Function()? currentUid}) => surfaceRecoveryOutcome(
      prefs: prefs,
      currentUid: currentUid ?? () => null,
      showSnack: (message, {bool isError = false}) =>
          snacks.add((message, isError)),
      capture: captures.add,
    );
```

New tests (the first is the #458 regression — the false-success case):

```dart
test('#458: success marker whose swap did NOT survive → failure notice', () async {
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
```

Existing tests need only the helper change (legacy markers have no `expectedUid`, so their behavior is unchanged — including 'successful restore → success snack' with the default `() => null` callback: that is exactly the legacy-marker trust path).

**Step 2: Run — expect compile failure (`currentUid` not a parameter)**

Run: `flutter test test/unit/recovery_outcome_notice_test.dart`
Expected: FAIL — `No named parameter with the name 'currentUid'`.

**Step 3: Implement**

Replace the body of `surfaceRecoveryOutcome`:

```dart
void surfaceRecoveryOutcome({
  required SharedPreferences prefs,
  required String? Function() currentUid,
  required void Function(String message, {bool isError}) showSnack,
  required void Function(String message) capture,
}) {
  final outcome = readAndClearRecoveryOutcome(prefs);
  if (outcome == null) return;

  if (!outcome.ok) {
    final code = outcome.code ?? 'unknown';
    showSnack(humanizeAuthErrorCode(code), isError: true);
    capture('recovery_failed op=${outcome.op} code=$code');
    return;
  }

  // A successful sign-out needs no toast — the fresh anonymous home says it.
  if (outcome.op != RecoveryOutcome.opGoogle &&
      outcome.op != RecoveryOutcome.opRecover) {
    return;
  }

  // #458: ok only proves the auth API call succeeded BEFORE the forced
  // restart — the swap is real only if it survived the process kill. When
  // the marker names the expected UID, the live UID is the truth; when auth
  // is unreadable we trust the claim rather than false-alarm.
  final expected = outcome.expectedUid;
  if (expected != null) {
    final bool verified;
    String? uid;
    try {
      uid = currentUid();
      verified = true;
    } catch (_) {
      verified = false;
    }
    if (verified && uid != expected) {
      showSnack(
        "Account restore didn't complete. Please try again.",
        isError: true,
      );
      capture('recovery_swap_not_durable op=${outcome.op}');
      return;
    }
  }

  showSnack('Account restored.', isError: false);
}
```

Also update the function doc comment to mention the verification (one sentence).

**Step 4: Run — expect pass**

Run: `flutter test test/unit/recovery_outcome_notice_test.dart`
Expected: PASS (new + all pre-existing).

**Step 5: Commit**

```bash
git add lib/features/auth/services/recovery_outcome_notice.dart test/unit/recovery_outcome_notice_test.dart
git commit -m "feat(auth): boot notice verifies the swap survived before claiming success (Refs #458)"
```

### Task 3: Restore success paths write the expected UID

**Files:**
- Modify: `lib/features/auth/services/auth_recovery_service.dart:288,355`
- Test: `test/unit/auth_recovery_service_outcome_marker_test.dart`

**Step 1: Write the failing assertions**

Read the test file first. In its existing `restoreWithGoogle` success-marker test (and the email-link analog), the mocked `UserCredential.user.uid` is already stubbed — extend the decoded-marker assertions with:

```dart
expect(decoded['expectedUid'], '<the stubbed swapped uid>');
```

If a success test asserts the exact `toJson` map, update it to include the new key. Sign-out success test: assert `expectedUid` is ABSENT (`decoded.containsKey('expectedUid'), isFalse`).

**Step 2: Run — expect failure (key absent)**

Run: `flutter test test/unit/auth_recovery_service_outcome_marker_test.dart`
Expected: FAIL on the new assertions only.

**Step 3: Implement**

`restoreWithGoogle` success site (`:288`):

```dart
await writeRecoveryOutcome(
  _prefs,
  op: RecoveryOutcome.opGoogle,
  ok: true,
  expectedUid: result.user?.uid,
);
```

`restoreWithEmailLink` success site (`:355`): add `expectedUid: result.user?.uid,` the same way. Failure sites and `signOutCurrentDevice` untouched.

Note (Gate R1 P3): a theoretically-null `result.user` writes `expectedUid: null`, which the reader treats as a legacy marker → trust-the-claim. That degradation is the safe direction (no false alarm) and is accepted.

**Step 4: Run — expect pass**

Run: `flutter test test/unit/auth_recovery_service_outcome_marker_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/features/auth/services/auth_recovery_service.dart test/unit/auth_recovery_service_outcome_marker_test.dart
git commit -m "feat(auth): restore swaps stamp the expected post-swap UID into the outcome marker (Refs #458)"
```

### Task 4: Wire the provider + full verification

**Files:**
- Modify: `lib/features/auth/providers/recovery_outcome_notice_provider.dart`

**Step 1: Wire the live UID**

Add import `../../../core/config/firebase_config.dart` and pass:

```dart
surfaceRecoveryOutcome(
  prefs: prefs,
  // Throws [core/no-app] when Firebase is absent — surfaceRecoveryOutcome
  // guards the call (CLAUDE.md gotcha: currentUser throws, not null).
  currentUid: () => FirebaseConfig.currentUser?.uid,
  ...
);
```

**Step 2: Analyze + full suite**

Run: `flutter analyze` → expect clean.
Run: `flutter test` → expect all green.

**Step 3: Commit**

```bash
git add lib/features/auth/providers/recovery_outcome_notice_provider.dart
git commit -m "feat(auth): boot notice reads the live UID for swap verification (Closes #458)"
```

### Task 5: PR + review-gated merge

**Step 1:** Push branch, open PR with `Closes #458`, a `Spec:` line pointing at this plan doc, and the RED evidence (failing-test output from Task 2 Step 2) in the body.

**Step 2:** Run `/automerge <N>` — `**/models/**` is not touched, but the marker is a persisted data shape with read+write paths; the classifier fails toward GATE, so expect the fresh-context diff review + refuter. Do not raw `gh pr merge`.

---

## Out of scope (surfaced, not bundled)

- Sign-out durability verification (no false-success risk: sign-out success shows no notice). If wanted later: embed the *outgoing* UID and alarm when it's still the live UID at boot.
- Localizing the bootstrap snackbar surface (tracked debt; this surface is hardcoded English on purpose).
- `showSnack` silently dropping when `appMessengerKey.currentState` is null after the marker was consumed — checked per the issue's parenthetical: on cold boot the messenger mounts before the post-frame callback, so this is theoretical; noted here rather than coded around.
