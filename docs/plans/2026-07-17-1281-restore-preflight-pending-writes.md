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
  - `lib/features/auth/widgets/durable_credential_sheet.dart` `_switchAccount` (:224, catch at :248-258 — NOTE the method is `_switchAccount`, not "_restoreFromConflict"): `catch (e, st)` → `Sentry.captureException` + `_errorText = durableGateError` + `_clearConflict()`. Comment confirms only pre-isolation failures reach it. The build renders `_errorText` ONLY in the `conflict == null` branch (:289) — load-bearing for Decision 6.
  - `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart` (:150-255): blocked-recover precedent at :179-204 (clear `inFlightOp`+`pendingEmail` guarded, error snack, no restart); generic `catch` at :243 does `Sentry.captureException` + `authEmailLinkGenericError`.
- Why the gate doesn't already cover this: `outgoingShellProvablyEmpty` checks only server-visible group membership (`readUser`/`readGroups`/`probeHasLiveData`) — zero references to pending writes. Fully offline, the server probe fails → gate blocks. The exposed window is **online with unflushed queued writes** (e.g. replay in progress after reconnect).

## Decisions (rationale the reviewers should attack)

1. **Preflight placement: very top of each restore fn** (before the interactive credential factory, before `_removeFcmTokenBestEffort`, before `engageIsolation`). Cheapest abort — no wasted Google/Apple sheet, shell untouched, no restart. Residual: writes queued *during* the interactive sheet window are not preflighted; the existing post-isolation best-effort wait stays (unchanged) as defense in depth. Aborting post-isolation is NOT acceptable (the `finally` restarts regardless — a heavy restart just to say "try again").
2. **No recovery-outcome marker on preflight abort.** The #439 marker exists because the restart kills the process before the caller can surface anything; a preflight abort has no restart, so the caller's snackbar/error-text surfacing works normally.
3. **No discard option on restores** (unlike `SignOutPendingWritesDialog`). Discarding queued writes to force a swap is the data-loss we're preventing; a user who truly wants that has the sign-out flow's explicit discard.
4. **Not a Sentry exception anywhere.** Expected user-state (mirrors the #1149 "expected states never Sentry" rule). Breadcrumb/log only.
5. **Bootstrap abort does NOT clear op-state (Gate R1 reversal — both reviewers converged).** The blocked-recover path (:179-204) clears `inFlightOp`+`pendingEmail` because a shell-with-data block is *durable* — a lingering op would phantom-re-dispatch forever (R3 P2-4). A pending-writes abort is *transient*: leaving the op-state primed is inert until a link arrives (op-state is only consulted at link-dispatch time), and it lets a later re-tap/next-boot link arrival auto-retry and succeed once writes flush. Clearing would instead break both retry routes: a same-session re-tap is `seenKeys`-deduped (:112) and a cold-restart re-tap would hit `pendingEmail == null` (:127) → "no pending email" dead end. So: log + Sentry breadcrumb + specific error snack ONLY; no prefs writes.
6. **Durable sheet CLEARS the conflict on this abort (Gate R1 reversal).** The build renders `_errorText` only in the `conflict == null` branch (durable_credential_sheet.dart:289); with `_conflict` held, the FutureBuilder branch renders `_switchOfferContent`/`_conflictDeadEndText` and the message would be invisible — a silent no-op loop. So the abort branch mirrors the generic path: `_restoring = false; _clearConflict(); _errorText = still-syncing copy` — the copy actually renders, and a retry re-raises the conflict → Switch offer again. (Retry costs re-running the link attempt; acceptable, matches the generic-error UX.)
7. **Exception message generalized** from "before sign-out" to "before a cross-UID swap" (it now guards four paths). Type-only assertions in existing tests (`isA<PendingWritesNotFlushedException>()`) are unaffected — no test asserts `.message` (verified in Gate R1).
8. **This spec REVERSES the deliberate #412/#664 proceed-on-timeout decision for the three restores — on purpose, and only pre-isolation.** The "restoring anyway" bounded-wait existed so an offline/hung flush could never stall the flow before the guaranteed restart (no stranded overlay). The preflight keeps the bounded wait (5s timeout, no hang) but flips the outcome to abort — safe *because it runs pre-isolation*: no overlay is up, nothing is stranded, the caller surfaces a snackbar and the shell is intact. The calculus flipped with #648/#818: an anon shell can now own groups, so a queued founding batch destroyed by the swap is real data loss. The post-isolation best-effort wait keeps the original #412/#664 protection inside the irreversible section, unchanged. Three existing tests pin the OLD behavior by name — "still swaps and restarts when waitForPendingWrites exceeds the timeout" (`auth_recovery_service_google_restore_test.dart:191`, `auth_recovery_service_apple_test.dart:317`, `auth_recovery_service_email_restore_test.dart:201`, each asserting `events == ['removeToken','engage','signIn','restart']`) — they are REWRITTEN by this spec (Task 1), not accidentally broken: new name "aborts before the swap when waitForPendingWrites exceeds the timeout", new assertions `throwsA(isA<PendingWritesNotFlushedException>())` and `events == []`.

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
- Caller branches (each BEFORE the existing generic catch). All three widget files need a NEW import: `import '../services/auth_recovery_service.dart';` — none currently imports it, and `auth_provider.dart` does not re-export it (verified R1):
  - `google_restore_action.dart` / `apple_restore_action.dart`: `on PendingWritesNotFlushedException { if (!context.mounted) return; _snack(context, context.l10n.restorePendingWritesNotSynced); }`
  - `durable_credential_sheet.dart` `_switchAccount`: `on PendingWritesNotFlushedException { if (!mounted) return; setState(() { _restoring = false; _clearConflict(); _errorText = context.l10n.restorePendingWritesNotSynced; }); }` — no Sentry; conflict cleared so the text renders in the :289 branch (Decision 6).
  - `auth_email_link_bootstrap_provider.dart`: `on PendingWritesNotFlushedException` → `FirebaseConfig.log`, Sentry **breadcrumb** (category `auth.recovery`, message `recover swap aborted (pending writes)`), `_showSnack(_l10n()?.restorePendingWritesNotSynced ?? 'Your recent changes are still syncing. Try again in a moment.', isError: true)`. NO op-state clearing (Decision 5).
- Ordering doc-comment: the numbered protocol comment above `restoreWithGoogle` (auth_recovery_service.dart:324-341, "1. Obtain the credential…") gains the preflight as its new step 1 and renumbers the rest — leaving it stale would misdocument the load-bearing order.

## Tasks

### Task 1: Service RED tests

**Files:**
- Modify: `test/unit/auth_recovery_service_google_restore_test.dart`
- Modify: `test/unit/auth_recovery_service_apple_test.dart`
- Modify: `test/unit/auth_recovery_service_email_restore_test.dart`

**Step 1:** Each of the three files carries a test named **"still swaps and restarts when waitForPendingWrites exceeds the timeout"** (`google_restore_test.dart:191`, `apple_test.dart:317`, `email_restore_test.dart:201`) pinning the OLD proceed-on-timeout behavior with `events == ['removeToken','engage','signIn','restart']`. REWRITE each in place (Decision 8): rename to "aborts before the swap when waitForPendingWrites exceeds the timeout"; keep the never-completing `Completer` stub; assert:
- the restore throws `PendingWritesNotFlushedException`;
- `events == []` — `removeToken`/`engageIsolation`/`signIn*`/`restart()` all never ran;
- the credential factory never called;
- no recovery-outcome marker was written (the file's existing prefs/outcome helpers).

**Step 2:** Run: `flutter test test/unit/auth_recovery_service_google_restore_test.dart test/unit/auth_recovery_service_apple_test.dart test/unit/auth_recovery_service_email_restore_test.dart` — expect the three REWRITTEN tests FAIL (current code proceeds and calls signIn: events sequence non-empty, no throw). Paste output. No other test in these files may go red (the `:79/:122/:148/:171`-class order-of-events tests stub a fast-resolving flush and stay green).

### Task 2: Service implementation

**Files:**
- Modify: `lib/features/auth/services/auth_recovery_service.dart`

Add `_flushPendingWritesOrThrow`; insert the preflight call at the top of the three restores; swap `signOutCurrentDevice`'s inline block to the helper; generalize the exception message; renumber the :324-341 ordering doc-comment (preflight = new step 1). Do NOT touch the post-isolation waits or their inline comments.

**Step 2:** Re-run Task 1's files — GREEN (including the three rewritten tests). Then the full service set: the three restore files + `auth_recovery_service_test.dart` + `auth_recovery_service_restart_guarantee_test.dart` + `auth_recovery_service_outcome_marker_test.dart` + `auth_recovery_service_inflight_op_test.dart` + `auth_recovery_service_google_link_test.dart` — green. Sign-out semantics are unchanged (`profile_screen.dart:529`'s existing `PendingWritesNotFlushedException` handler is sign-out-only and unaffected).

**Step 3:** Commit `fix(auth): preflight pending-writes flush before cross-UID restore swaps` (body: `Refs #1281` — full close happens with the caller surfacing PR-complete).

### Task 3: Caller RED tests + implementation

**Files:**
- Modify: `test/features/auth/google_restore_guard_test.dart`, `test/features/auth/apple_restore_guard_test.dart` (still-syncing snackbar on `PendingWritesNotFlushedException` from a mocked service)
- Modify: `test/features/auth/durable_credential_sheet_conflict_test.dart` (conflict-switch abort → still-syncing copy IS rendered — reachable because the conflict is cleared per Decision 6 — and no Sentry capture)
- Modify: `test/unit/auth_email_link_bootstrap_test.dart` (recover abort → specific snack, `inFlightOp`+`pendingEmail` NOT cleared — pins Decision 5 — and no `captureException`)
- Modify: the four caller files (including the three new `auth_recovery_service.dart` imports) + both arbs per the data contracts above.

RED first per file, then implement, then GREEN. `flutter gen-l10n` runs via build; add the key to BOTH arbs in the same commit (generated_l10n_surface_test enumerates keys — an EN-only key goes red).

**Step N:** Commit `fix(auth): surface retryable still-syncing state on restore preflight abort` (body: `Closes #1281`).

### Task 4: Full verification

`flutter analyze` clean; `flutter test test/unit/ test/features/auth/`; `bash tool/check_theme_purity.sh`. Then full `flutter test`.

## Out of scope (explicit)

- Wiring pending-writes into `outgoingShellProvablyEmpty` (the gate stays membership-only; the preflight is the enforcement point).
- Any change to `SignOutPendingWritesDialog` / sign-out UX.
- The restores' post-isolation best-effort waits.
- deleteAccount (its cascade is server-side; different protocol).
