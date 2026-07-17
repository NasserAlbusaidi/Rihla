# Restore-Swap Pending-Writes Preflight Guard (#1281) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Abort the three cross-UID restore/swap paths *before* the irreversible section when pending Firestore writes don't flush, instead of logging "restoring anyway" and destroying them.

**Architecture:** Move the pending-writes check to a pre-flight at the top of each restore function — the exact shape `signOutCurrentDevice` already has (its check runs BEFORE `engageIsolation()`, so an abort leaves the shell intact with no restart). A shared private helper replaces four near-identical blocks. Callers get a specific, retryable "still syncing" surface; the abort is an expected user-state, never a Sentry exception.

**Tech Stack:** Dart/Flutter, mocktail, existing `test/unit/auth_recovery_service_*` harness.

**Spec:** this document. **Issue:** #1281.

---

## Verified current state (all re-read 2026-07-17 on main @ 97301000)

- `lib/features/auth/services/auth_recovery_service.dart`
  - `PendingWritesNotFlushedException` (:35-38) — message says "before sign-out".
  - `restoreWithGoogle` (:342): `_removeFcmTokenBestEffort` (:353) → `engageIsolation()` (:355) → **inside the guaranteed-restart try**: `waitForPendingWrites().timeout` catching `TimeoutException` → log "restoring anyway" (:357-365).
  - `restoreWithApple` (:398): identical protocol (:410-422).
  - `restoreWithEmailLink` (:461): identical (:479-491), plus op-state clear in `finally` (:516-525).
  - `signOutCurrentDevice` (:562): pre-flight `if (!discardPendingWrites) { wait → on TimeoutException throw PendingWritesNotFlushedException }` (:572-579) **before** fcm removal/isolation — the pattern this plan generalizes.
- Callers and their current error handling:
  - `lib/features/auth/widgets/google_restore_action.dart` (:38-48): `catch (_)` → `restoreGoogleFailed` snack.
  - `lib/features/auth/widgets/apple_restore_action.dart` (:38-48): same shape, `restoreAppleFailed`.
  - `lib/features/auth/widgets/durable_credential_sheet.dart` `_restoreFromConflict` (:240-258): `catch (e, st)` → `Sentry.captureException` + `_errorText = durableGateError` + `_clearConflict()`. Comment confirms only pre-isolation failures reach it.
  - `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart` (:150-255): blocked-recover precedent at :179-204 (clear `inFlightOp`+`pendingEmail` guarded, error snack, no restart); generic `catch` at :243 does `Sentry.captureException` + `authEmailLinkGenericError`.
- Why the gate doesn't already cover this: `outgoingShellProvablyEmpty` checks only server-visible group membership (`readUser`/`readGroups`/`probeHasLiveData`) — zero references to pending writes. Fully offline, the server probe fails → gate blocks. The exposed window is **online with unflushed queued writes** (e.g. replay in progress after reconnect).

## Decisions (rationale the reviewers should attack)

1. **Preflight placement: very top of each restore fn** (before the interactive credential factory, before `_removeFcmTokenBestEffort`, before `engageIsolation`). Cheapest abort — no wasted Google/Apple sheet, shell untouched, no restart. Residual: writes queued *during* the interactive sheet window are not preflighted; the existing post-isolation best-effort wait stays (unchanged) as defense in depth. Aborting post-isolation is NOT acceptable (the `finally` restarts regardless — a heavy restart just to say "try again").
2. **No recovery-outcome marker on preflight abort.** The #439 marker exists because the restart kills the process before the caller can surface anything; a preflight abort has no restart, so the caller's snackbar/error-text surfacing works normally.
3. **No discard option on restores** (unlike `SignOutPendingWritesDialog`). Discarding queued writes to force a swap is the data-loss we're preventing; a user who truly wants that has the sign-out flow's explicit discard.
4. **Not a Sentry exception anywhere.** Expected user-state (mirrors the #1149 "expected states never Sentry" rule). Breadcrumb/log only.
5. **Bootstrap abort mirrors the blocked-recover path** (:179-204): clear `inFlightOp` + `pendingEmail` (guarded) so a phantom op never re-dispatches on later boots (R3 P2-4), show a specific error snack. The abort happens BEFORE `signInWithEmailLink`, so the email link is unconsumed — the user re-taps the same link (or resends) once syncing settles.
6. **Durable sheet keeps `_conflict` intact on this abort** (deviation from the generic path's `_clearConflict()`): the state is retryable, and clearing would force the user to re-run the failed link attempt just to re-obtain the credential. `_restoring` resets to false.
7. **Exception message generalized** from "before sign-out" to "before a cross-UID swap" (it now guards four paths). Type and semantics unchanged.

## Data contracts (exact)

- New private helper in `AuthRecoveryService`:
  ```dart
  /// Pre-flight for every cross-UID swap: flush pending writes or abort while
  /// the shell is still intact (#1281 — the restores previously logged
  /// "restoring anyway" here, silently destroying queued writes).
  Future<void> _flushPendingWritesOrThrow(Duration timeout) async {
    try {
      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.waitForPendingWrites().timeout(timeout);
    } on TimeoutException {
      throw PendingWritesNotFlushedException(timeout);
    }
  }
  ```
- Call added as the FIRST await in `restoreWithGoogle` / `restoreWithApple` (before the credential factory) and in `restoreWithEmailLink` immediately after the email null-check. `signOutCurrentDevice`'s inline block (:572-579) is replaced by `if (!discardPendingWrites) { await _flushPendingWritesOrThrow(pendingWritesTimeout); }` — behavior identical.
- The post-isolation best-effort waits (:357-365, :414-422, :483-491) are UNTOUCHED, including their log strings and ordering doc comments (load-bearing per the method docs).
- New l10n key, both arbs: `restorePendingWritesNotSynced`
  - `lib/l10n/app_en.arb`: `"Your recent changes are still syncing. Try again in a moment."`
  - `lib/l10n/app_ar.arb`: `"ما زالت تغييراتك الأخيرة قيد المزامنة. حاول مرة أخرى بعد قليل."`
- Caller branches (each BEFORE the existing generic catch):
  - `google_restore_action.dart` / `apple_restore_action.dart`: `on PendingWritesNotFlushedException { if (!context.mounted) return; _snack(context, context.l10n.restorePendingWritesNotSynced); }`
  - `durable_credential_sheet.dart` `_restoreFromConflict`: `on PendingWritesNotFlushedException { if (!mounted) return; setState(() { _restoring = false; _errorText = context.l10n.restorePendingWritesNotSynced; }); }` — no Sentry, `_conflict` kept.
  - `auth_email_link_bootstrap_provider.dart`: `on PendingWritesNotFlushedException` → `FirebaseConfig.log`, Sentry **breadcrumb** (category `auth.recovery`, message `recover swap aborted (pending writes)`), guarded `clearInFlightOp()`+`clearPendingEmail()` (copy the :185-193 shape), `_showSnack(_l10n()?.restorePendingWritesNotSynced ?? 'Your recent changes are still syncing. Try again in a moment.', isError: true)`.

## Tasks

### Task 1: Service RED tests

**Files:**
- Modify: `test/unit/auth_recovery_service_google_restore_test.dart`
- Modify: `test/unit/auth_recovery_service_apple_test.dart`
- Modify: `test/unit/auth_recovery_service_email_restore_test.dart`

**Step 1:** In each, add a test: mock `firestore.waitForPendingWrites()` to throw `TimeoutException` (or return a `Completer.future` that never completes, then rely on the injected short `pendingWritesTimeout`). Follow each file's existing mock wiring. Assert:
- the restore throws `PendingWritesNotFlushedException`;
- `cacheIsolationController.engageIsolation` was **never** called;
- `auth.signInWithCredential` / `signInWithEmailLink` never called;
- `restart()` never called;
- the credential factory / FCM remover never called;
- no recovery-outcome marker was written (assert via the file's existing prefs/outcome helpers).

**Step 2:** Run: `flutter test test/unit/auth_recovery_service_google_restore_test.dart test/unit/auth_recovery_service_apple_test.dart test/unit/auth_recovery_service_email_restore_test.dart` — expect the new tests FAIL (current code proceeds and calls signIn). Paste output.

### Task 2: Service implementation

**Files:**
- Modify: `lib/features/auth/services/auth_recovery_service.dart`

Add `_flushPendingWritesOrThrow`; insert the preflight call at the top of the three restores; swap `signOutCurrentDevice`'s inline block to the helper; generalize the exception message. Do NOT touch the post-isolation waits or their comments beyond what the diff requires.

**Step 2:** Re-run Task 1's files — GREEN. Then the full existing service suite: `flutter test test/unit/ -x` (or the auth_recovery set + `auth_recovery_service_restart_guarantee_test.dart` + `auth_recovery_service_outcome_marker_test.dart` + `auth_recovery_service_inflight_op_test.dart`) — all green (sign-out semantics unchanged).

**Step 3:** Commit `fix(auth): preflight pending-writes flush before cross-UID restore swaps` (body: `Refs #1281` — full close happens with the caller surfacing PR-complete).

### Task 3: Caller RED tests + implementation

**Files:**
- Modify: `test/features/auth/google_restore_guard_test.dart`, `test/features/auth/apple_restore_guard_test.dart` (still-syncing snackbar on `PendingWritesNotFlushedException` from a mocked service)
- Modify: `test/features/auth/durable_credential_sheet_conflict_test.dart` (conflict-switch abort → `_errorText` copy shown, conflict CTA still present, no Sentry)
- Modify: `test/unit/auth_email_link_bootstrap_test.dart` (recover abort → op-state cleared, specific snack, no `captureException`)
- Modify: the four caller files + both arbs per the data contracts above.

RED first per file, then implement, then GREEN. `flutter gen-l10n` runs via build; add the key to BOTH arbs in the same commit (generated_l10n_surface_test enumerates keys — an EN-only key goes red).

**Step N:** Commit `fix(auth): surface retryable still-syncing state on restore preflight abort` (body: `Closes #1281`).

### Task 4: Full verification

`flutter analyze` clean; `flutter test test/unit/ test/features/auth/`; `bash tool/check_theme_purity.sh`. Then full `flutter test`.

## Out of scope (explicit)

- Wiring pending-writes into `outgoingShellProvablyEmpty` (the gate stays membership-only; the preflight is the enforcement point).
- Any change to `SignOutPendingWritesDialog` / sign-out UX.
- The restores' post-isolation best-effort waits.
- deleteAccount (its cascade is server-side; different protocol).
