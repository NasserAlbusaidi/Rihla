# Recovery Diagnostics + Visible Failure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make email-link account-recovery failures (a) visible to the user after the forced restart and (b) diagnosable from Sentry in release builds — without leaking PII or changing any data-safety behavior.

**Architecture:** The recovery path (`completeRecovery`) ends in an unconditional native `System.exit(0)` restart, which pre-empts the existing error SnackBar and discards in-flight async Sentry sends. So we (1) persist a PII-safe failure marker to `SharedPreferences` *before* `restart()`, (2) on the next cold boot — a stable process — surface a user-facing message *and* emit the authoritative Sentry event, then clear the marker, and (3) add PII-safe Sentry breadcrumbs/captures to the *non-restarting* recovery paths (send link, link-email, bootstrap dispatch) where immediate capture is safe. Today the only signal is `FirebaseConfig.log`, which is `kDebugMode`-only (`dart:developer`) and never reaches Sentry — release-build recovery failures are blind.

**Tech Stack:** Flutter, Riverpod, `firebase_auth`, `sentry_flutter` (already initialized in `main.dart`, error `sampleRate` defaults to 1.0), `shared_preferences`. No new dependencies.

---

## Background (verified against code, 2026-06-10)

- `lib/features/auth/services/auth_recovery_service.dart:257-349` — `completeRecovery`. `signInWithEmailLink` (`:316`) throws on a dead link; there is **no `signOut`** on failure (`:312-315`, pinned by `verifyNever(signOut)` in the existing test). The `finally` (`:339-348`) always runs `_safeClearRecoveryOpState()` then `_cacheIsolationController.restart()`.
- `android/app/src/main/kotlin/com/safar/safar/MainActivity.kt` — the `restart` channel handler calls `restartApp()` which calls `Runtime.getRuntime().exit(0)` **synchronously** before `result.success(null)`. ⇒ `await restart()` never returns; nothing after it runs; the rethrow never reaches the bootstrap `catch` at `auth_email_link_bootstrap_provider.dart:162`; the `_humanize` SnackBar (`:172`) never renders. **The failure is invisible.**
- `lib/core/config/firebase_config.dart` — `FirebaseConfig.log` is `kDebugMode`-only and uses `dart:developer` (NOT Sentry). The cleanup-failure breadcrumb (`auth_recovery_service.dart:126-140`) is the only existing Sentry signal, and nothing in the recover path *captures an event*, so breadcrumbs never flush.
- `lib/features/auth/services/auth_email_link_config.dart:67-78` — `redactForLogging` already strips `oobCode`/`apiKey`. Reuse it; never log raw links/emails.
- `lib/core/services/cache_uid_barrier.dart` — the cold-boot reconcile pattern + `markFirestorePersistenceDirty` is the precedent for "write a durable prefs marker before restart, consume on next boot."
- `lib/core/services/app_messenger.dart` — `appMessengerKey` (root `ScaffoldMessenger`, mounted `main.dart:225`) is the context-free SnackBar surface; already used by the bootstrap.
- `lib/core/providers/app_bootstrap_provider.dart:11` — watches `authEmailLinkBootstrapProvider`; the natural home for a one-shot post-boot surfacing effect.

## Scope decisions (locked)

- **In scope:** recovery/auth flow only (per user). Diagnostics on `completeRecovery`, `completeEmailLink`, `linkEmailToCurrentUser`, `sendRecoveryLink`, and the bootstrap `handleUri`; + the visible-failure marker/surface.
- **English messages**, reusing the existing `_humanize` mapping. The whole recovery UX is currently English-only (`_humanize` is hardcoded English); localizing one message while the rest stays English would be inconsistent. l10n of recovery copy is a separate follow-up, not this PR.
- **No consolidation** of the existing `_recoveryCleanupFailureRecorder` into the new diagnostics seam (minimal diff; avoid regressing cleanup tests). Note as follow-up.
- **No data-safety behavior changes.** The new try/catch in `completeRecovery` *rethrows* — `signInWithEmailLink` failure still propagates, `finally` still restarts, `signOut` is still never called.

## Verification principles (run on this plan)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).** New prefs key `auth.recoveryFailure`: **OUTBOUND** at the `completeRecovery` catch (write), **INBOUND** at the post-boot surface (read+display+clear). No money/Firestore write path touched. The marker value is a fixed enum-ish `{code, op}` — `code` comes from `FirebaseAuthException.code` (a Firebase-controlled string), `op` from our own `opLink`/`opRecover` constants. Display-only on read.
2. **Concrete claims vs code.** All file:line refs above re-verified this session by Read. `error sampleRate` default = 1.0 confirmed (`main.dart:59-61` sets only `tracesSampleRate`/`profilesSampleRate`).
3. **One read-path per write-path.** Marker written at `completeRecovery` catch → read by exactly one consumer (`consumeRecoveryFailureNotice` in the post-boot surface). No other reader. Cleared after display (one-shot).
4. **Enumerate fields from the type.** Marker is `{code: String, op: String}` (jsonEncoded). No UID, no email, no link, no oobCode.
5. **Data contracts spelled out.** `RecoveryDiagnostics` interface: `breadcrumb(String phase, {Map<String,Object?> data})`, `captureFailure(String phase, {required String code, Map<String,Object?> data})`, `fingerprint(String uid) -> String`. Marker JSON keys exactly `code`, `op`.
6. **Arithmetic decomposition.** N/A (no money math touched).
7. **Adversarial pass on orthogonal axis.** Fix is on the observability/UX axis; the adversarial example exercises the **data-safety axis**: a `completeRecovery` whose `signInWithEmailLink` throws must STILL (a) never call `signOut`, (b) still call `restart()` via `finally`, (c) still rethrow, (d) leave the original UID intact, AND now (e) write the marker before restart and (f) leak no PII into the marker or breadcrumbs. Task 4's tests assert exactly this.

**Gate:** This modifies `completeRecovery` (the #213/#414 blast-radius function) and adds a persisted marker with read+write paths → run `/run-the-gate` (fresh-context Opus) on this plan before Task 1. Apply P1s, re-run with a new subagent until clean.

---

## Task 1: Extract `humanizeAuthErrorCode` (pure, reused by live catch + post-boot surface)

**Files:**
- Modify: `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart:62-83`
- Test: `test/features/auth/auth_email_link_bootstrap_test.dart` (create if absent) OR a small `test/unit/humanize_auth_error_code_test.dart`

**Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';

void main() {
  test('maps expired/invalid action codes to the resend message', () {
    expect(humanizeAuthErrorCode('expired-action-code'),
        'This link has expired or was already used. Send a new one.');
    expect(humanizeAuthErrorCode('invalid-action-code'),
        'This link has expired or was already used. Send a new one.');
  });

  test('falls back with the raw code for unknown codes', () {
    expect(humanizeAuthErrorCode('weird-code'), contains('weird-code'));
  });
}
```

**Step 2: Run, expect FAIL** — `humanizeAuthErrorCode` undefined.
Run: `flutter test test/unit/humanize_auth_error_code_test.dart`

**Step 3: Implement** — add a top-level `String humanizeAuthErrorCode(String code)` containing the current `switch`, and reduce `_humanize` to `=> humanizeAuthErrorCode(error.code)`. Keep `_humanize` private wrapper so existing callsite (`:172`) is unchanged.

**Step 4: Run, expect PASS.** Then `flutter test test/features/auth/` to confirm no regression.

**Step 5: Commit** — `refactor(auth): extract humanizeAuthErrorCode for reuse`

---

## Task 2: `RecoveryDiagnostics` seam + default Sentry impl + uid fingerprint

**Files:**
- Create: `lib/features/auth/services/recovery_diagnostics.dart`
- Test: `test/unit/recovery_diagnostics_test.dart`

**Design:**

```dart
abstract class RecoveryDiagnostics {
  void breadcrumb(String phase, {Map<String, Object?> data});
  void captureFailure(String phase, {required String code, Map<String, Object?> data});
  /// Stable, non-reversible short fingerprint of a UID for correlation
  /// (FNV-1a, 8 hex). NOT a security control — just lets two breadcrumbs
  /// about the same session be linked without logging the raw UID.
  static String fingerprint(String uid) { /* FNV-1a over UTF-8 bytes -> 8 hex */ }
}

class SentryRecoveryDiagnostics implements RecoveryDiagnostics {
  const SentryRecoveryDiagnostics();
  // breadcrumb -> Sentry.addBreadcrumb(category: 'auth.recovery', level: info)
  // captureFailure -> addBreadcrumb(level: error) + Sentry.captureMessage(
  //   'Recovery failed: $phase ($code)', level: error, withScope: tags)
}
```

**Step 1: Write failing tests** (`RecordingRecoveryDiagnostics` fake records calls; assert):
- `fingerprint` is deterministic, 8 lowercase hex chars, and `fingerprint('a') != fingerprint('b')`.
- `fingerprint` of a 28-char Firebase UID does not contain any 4+ char substring of the input (non-reversible smoke check).

**Step 2: Run, expect FAIL.**

**Step 3: Implement** the FNV-1a fingerprint + the Sentry impl. (Sentry calls are fire-and-forget `unawaited` like the existing breadcrumb recorder; do not block the flow.)

**Step 4: Run, expect PASS.**

**Step 5: Commit** — `feat(auth): add PII-safe RecoveryDiagnostics seam`

---

## Task 3: Failure-marker write/read helpers (pure, prefs-backed)

**Files:**
- Modify: `lib/features/auth/services/auth_recovery_service.dart` (add keys + static helpers) OR a new `lib/features/auth/services/recovery_failure_notice.dart` (preferred — keeps the service lean and the helpers independently testable)
- Test: `test/unit/recovery_failure_notice_test.dart`

**Design (new file `recovery_failure_notice.dart`):**

```dart
const String kRecoveryFailureKey = 'auth.recoveryFailure';

class RecoveryFailureNotice {
  const RecoveryFailureNotice({required this.code, required this.op});
  final String code; // FirebaseAuthException.code
  final String op;   // AuthRecoveryService.opRecover | opLink
}

Future<void> writeRecoveryFailureNotice(SharedPreferences prefs,
    {required String code, required String op}) =>
  prefs.setString(kRecoveryFailureKey, jsonEncode({'code': code, 'op': op}));

/// Reads WITHOUT clearing (so a failed display doesn't silently drop it).
RecoveryFailureNotice? readRecoveryFailureNotice(SharedPreferences prefs) { ... }

Future<void> clearRecoveryFailureNotice(SharedPreferences prefs) =>
  prefs.remove(kRecoveryFailureKey);
```

**Step 1: Write failing tests** (use `SharedPreferences.setMockInitialValues({})`):
- write → read round-trips `{code, op}`.
- read on empty prefs → `null`.
- read on a malformed/garbage string → `null` (never throws).
- clear → subsequent read is `null`.

**Step 2: Run, expect FAIL.**

**Step 3: Implement.** `read` wraps `jsonDecode` in try/catch → `null` on any error (boundary validation).

**Step 4: Run, expect PASS.**

**Step 5: Commit** — `feat(auth): recovery failure notice marker helpers`

---

## Task 4: Instrument `completeRecovery` — marker on failure + breadcrumbs (DATA-SAFETY CRITICAL)

**Files:**
- Modify: `lib/features/auth/services/auth_recovery_service.dart` (constructor: add `RecoveryDiagnostics diagnostics = const SentryRecoveryDiagnostics()`; wrap `signInWithEmailLink` in try/catch; add phase breadcrumbs)
- Test: `test/unit/auth_recovery_service_test.dart` (extend existing)

**Implementation shape** (inside `completeRecovery`, replacing the bare `signInWithEmailLink` call at `:316-319`):

```dart
_diagnostics.breadcrumb('recover.signIn.attempt',
    data: {'uid': oldUid == null ? null : RecoveryDiagnostics.fingerprint(oldUid)});
final UserCredential result;
try {
  result = await _auth.signInWithEmailLink(email: email, emailLink: emailLink);
} on FirebaseAuthException catch (e) {
  // Persist BEFORE the finally's restart (System.exit(0) discards async Sentry
  // sends and pre-empts the bootstrap SnackBar). Awaited so it is flushed.
  await writeRecoveryFailureNotice(_prefs, code: e.code, op: opRecover);
  _diagnostics.breadcrumb('recover.signIn.fail', data: {'code': e.code});
  rethrow; // unchanged behavior: propagate + let finally restart
}
_diagnostics.breadcrumb('recover.signIn.ok',
    data: {'uidChanged': result.user?.uid != oldUid});
// Belt-and-suspenders: clear any stale marker from a prior failed attempt so a
// later SUCCESS can't surface a false "expired" message on next boot (the
// narrow case where the post-boot surface didn't run after the prior restart).
await clearRecoveryFailureNotice(_prefs);
```

Also add `breadcrumb('recover.start', ...)` after isolation engages, and `breadcrumb('recover.restart')` at the top of `finally`. Reuse `FirebaseConfig.log` lines as-is.

**Step 1: Write failing tests** (extend existing; the existing `verifyNever(signOut)` + `events == ['engage','restart']` tests MUST stay green):
- *signInWithEmailLink throws `invalid-action-code`* ⇒ `writeRecoveryFailureNotice` persisted `{code:'invalid-action-code', op:'recover'}` to prefs (read it back), AND still rethrows, AND `verifyNever(signOut)`, AND restart still invoked. (assert via real `SharedPreferences.setMockInitialValues` + recording isolation controller)
- *signInWithEmailLink succeeds* ⇒ no failure marker present (read → null).
- *prior marker present + signInWithEmailLink succeeds* ⇒ marker cleared (read → null) — stale-marker guard.
- *diagnostics recorder receives no PII* — inject `RecordingRecoveryDiagnostics`, assert across all breadcrumb `data` maps: no value equals the email, no value contains `'oobCode'`/the raw link, and any `uid` value equals `fingerprint(oldUid)` (never the raw uid).

**Step 2: Run, expect FAIL** (marker not written / diagnostics not called).

**Step 3: Implement** the try/catch + breadcrumbs + constructor param.

**Step 4: Run, expect PASS** + full `flutter test test/unit/auth_recovery_service_test.dart`.

**Step 5: Commit** — `feat(auth): persist recovery failure marker + diagnostics breadcrumbs (no signOut)`

---

## Task 5: Instrument the non-restarting paths (immediate capture is safe here)

**Files:**
- Modify: `auth_recovery_service.dart` (`completeEmailLink`, `linkEmailToCurrentUser`, `sendRecoveryLink`)
- Modify: `auth_email_link_bootstrap_provider.dart` (`handleUri`: link-received / dedupe / no-pending-email / dispatch; and in the `catch` blocks call `diagnostics.captureFailure` for the **link** op only — the recover op already wrote the marker in Task 4)
- Test: extend `auth_recovery_service_test.dart` + a bootstrap test

**Note:** These paths do NOT restart, so `captureFailure` (immediate Sentry event) is reliable. `handleUri`'s diagnostics use the existing `redactForLogging` for any link reference.

**Steps:** RED test (recorder sees `link.start`/`link.ok`/`link.fail` with code, no PII) → implement → GREEN → commit `feat(auth): diagnostics on link/send/bootstrap recovery paths`.

---

## Task 6: Post-boot surface — show the message + emit authoritative Sentry event + clear

**Files:**
- Modify: `lib/core/providers/app_bootstrap_provider.dart` (add a one-shot post-frame effect) OR add to `authEmailLinkBootstrapProvider` body
- Create (optional): `lib/features/auth/providers/recovery_failure_surface.dart` (the wiring), keeping the pure read/clear in Task 3's file
- Test: `test/features/auth/recovery_failure_surface_test.dart` (widget test with `appMessengerKey` mounted)

**Behavior on cold boot, after first frame (messenger mounted):**
1. `notice = readRecoveryFailureNotice(prefs)`; if `null`, do nothing.
2. Show SnackBar via `appMessengerKey` with `humanizeAuthErrorCode(notice.code)` (isError).
3. `diagnostics.captureFailure('recover.surfaced', code: notice.code, data: {'op': notice.op})` — reliable here (stable process).
4. `await clearRecoveryFailureNotice(prefs)` — one-shot.

Use `WidgetsBinding.instance.addPostFrameCallback` so the `ScaffoldMessenger` is mounted (the existing `_showSnack` no-ops if `messenger == null` — the post-frame callback avoids that race).

**Step 1: Write failing widget test** — pump a minimal `MaterialApp(scaffoldMessengerKey: appMessengerKey)` with the surface wired and `SharedPreferences` mock-seeded with a failure notice; pump a frame; assert the resend SnackBar text is found AND the marker is cleared (`readRecoveryFailureNotice` → null) AND the recording diagnostics saw `recover.surfaced`.

**Step 2: Run, expect FAIL.**

**Step 3: Implement** the surfacing wiring.

**Step 4: Run, expect PASS.** Then `flutter test test/features/auth/`.

**Step 5: Commit** — `feat(auth): surface recovery failure after forced restart`

---

## Task 7: Full verification + analyze

**Steps:**
1. `flutter analyze` — must be clean (watch `prefer_const_constructors`).
2. `flutter test test/unit/ test/features/auth/` — all green, including the untouched `verifyNever(signOut)` and isolation-overlay tests.
3. Manual re-read of the `completeRecovery` diff: confirm `signOut` absent, `finally`/`restart` unchanged, rethrow intact, no email/link/oobCode/raw-uid in any marker or breadcrumb.
4. Commit any analyze fixups.

---

## PR

- Branch: `feat/recovery-diagnostics` (worktree `../Rihla-recovery-diag`).
- `Closes #<issue>` (file the issue: "Recovery failure is invisible after forced restart + no release-build diagnostics").
- Body: the invisible-failure root cause (MainActivity `exit(0)` pre-empts the SnackBar), the marker→post-boot design, RED-evidence per money/legal-adjacent area, and a `Spec:` line pointing here.
- Gate-classification for `/automerge`: touches `auth_recovery_service.dart` + a deep-link bootstrap surface → **expect Gate-category review** (fresh-context Opus diff review + refuter). Do not raw `gh pr merge`.

## Follow-ups (out of scope, note in PR)

- Consolidate `_recoveryCleanupFailureRecorder` into `RecoveryDiagnostics`.
- l10n of recovery copy (`humanizeAuthErrorCode` is English-only, matching current state).
