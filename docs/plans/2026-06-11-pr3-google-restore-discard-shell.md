# PR3 — Google restore (discard-shell cross-UID swap) + restore entries

**Epic:** #441 durable-credential re-architecture. **Issue:** #428 (re-scoped).
**Parent plan:** `docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md` (PR3 row).
**Branch:** `feat/durable-credential-restore-441-pr3` (worktree `../Rihla-441-pr3`, off PR1 `fcc4ae86`).
**Category:** Gate-category (auth swap paths + cross-UID isolation). `/run-the-gate` before code, `/automerge` review before merge.
**Spec:** this file (the `Spec:` line for the merge-time reviewer).

## What PR3 is (and is NOT)

PR3 adds the **cross-UID Google restore** — the path a user takes on a fresh device (or after losing their local shell) to sign back into the durable Google-backed account they linked at the gate (PR2). The swap mirrors the existing email-link `completeRecovery` engage→dirty→swap→restart skeleton **minus the merge engine** (the post-gate anon shell is provably empty, so there is nothing to migrate).

**In scope (decided 2026-06-11):**
1. `AuthRecoveryService.restoreWithGoogle({AuthCredential? credential})` — the discard-shell `signInWithCredential` swap.
2. A `removeFcmToken` injection seam on `AuthRecoveryService` so `removeToken()` runs **before** the swap, atomically inside the method.
3. Conflict classifier `isGoogleAccountAlreadyInUse(Object error)` — a pure, tested helper PR2's gate consumes (never reads `e.credential`).
4. Repoint **one** `/recover` pusher to the Google restore: the home empty-state CTA (`home_screen.dart:313`, key at `:312`). It is the canonical restore moment (fresh install → empty home) and is **provably safe**: `_buildEmpty` only renders on `groups.isEmpty` (`home_screen.dart:96-97`), so the shell has zero groups → zero money data → the discard-shell swap orphans nothing.
5. l10n for any new/changed labels (EN + AR).

**Out of scope (decided 2026-06-11):**
- **Profile `_PendingRecoveryBanner` repoint → NOT PR3 (Gate R1 [P1]).** That banner renders unconditionally on `pendingEmailLinkProvider != null` (`profile_screen.dart:258`, no group-count gate), and its copy is email-specific (`profileRecoverySubtitle` = "…Enter the email it was sent to", `app_en.arb:357`). Repointing its tap to the discard-shell `signInWithCredential` would (a) **orphan a non-empty anon shell** (data loss — no `groups.isEmpty` guard) and (b) be a semantic category error (a user who tapped an *email* link gets a *Google* sheet). It stays on `/recover` — it belongs to the email-link flow PR4 reworks. A dedicated Profile "Sign in with Google to restore" row rides with **PR2's account-section rework** (the natural home alongside the linked-state row), not the email banner.
- **Intent persistence across restart → PR3b.** Only the *gate-conflict* discard-shell (PR2's link → `credential-already-in-use` → switch) restarts mid-create/join; the home restore entry has nothing in-flight to resume. Split for reviewability; lands with/after PR2 wires the gate.
- **AccountBackupNudge repoint + Profile linked-state display row + Profile restore row → PR2.** Those live on the Profile *account/link* surface (durable-ify or display the current UID = the gate's job).
- **The gate-conflict dialog UI → PR2.** PR3 ships the resolution *machinery* (classifier + `restoreWithGoogle`); PR2 composes them with its gate copy.
- **Deleting `/recover` routes / recover screens / `MergeOnRecoverDialog` / `cleanupAnonUidArtifacts` → PR5.** They coexist harmlessly until PR3 is device-QA'd.

## The discard-shell swap — exact ordering (the load-bearing part)

`completeRecovery` (`auth_recovery_service.dart:294-386`) is the template; `signOutCurrentDevice` (`:498-526`) is the lean no-merge twin. The restore swap mirrors them with **one deliberate divergence**: the credential is obtained **interactively** (Credential Manager sheet), so it must be acquired **before** isolation engages — a user-cancel must abort with the anon shell fully intact.

```dart
Future<UserCredential> restoreWithGoogle({
  AuthCredential? credential,
  Duration pendingWritesTimeout = const Duration(seconds: 5),
}) async {
  // (1) Obtain the credential FIRST — BEFORE any isolation/auth change.
  //     Interactive: a cancel / missing idToken / missing serverClientId throws
  //     here, and the anon shell is untouched (no overlay, no restart, no swap).
  //     DIVERGENCE from completeRecovery (whose link arrives pre-obtained via the
  //     deep-link bootstrap). Documented because the Gate will flag the reorder.
  final googleCredential = credential ?? await _googleCredentialFactory();

  // (2) removeToken BEFORE the swap. Owner-only fcm_tokens rules
  //     (firestore.rules:171-173) make the old UID's token doc un-deletable once
  //     request.auth.uid changes. Resolved here (pre-engage) so it hits the live
  //     NotificationService instance and the still-current oldUid. Best-effort.
  //     NOTE (Gate R2 [P3]): removeToken()'s Firestore .delete() is try/caught,
  //     but its finally calls _cancelSubscriptions() UNGUARDED — a throwing
  //     sub.cancel() could propagate. Safety comes from PLACEMENT: this runs at
  //     step 2, BEFORE engageIsolation and outside the try/finally, so a rethrow
  //     aborts the restore with the anon shell fully intact (retryable, not data
  //     loss) — not from removeToken being throw-proof.
  await _removeFcmToken();

  // (3) Engage isolation — covers cached UI + tears down the leaf subscription
  //     holders — BEFORE the auth change.
  _cacheIsolationController.engageIsolation();

  // (4) try/finally GUARANTEES the restart on success AND failure.
  try {
    try {
      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
    } on TimeoutException {
      FirebaseConfig.log('Restore: waitForPendingWrites timed out — continuing');
    }
    // Durable cross-restart marker, awaited so it's flushed before the swap.
    await markFirestorePersistenceDirty(_prefs);
    // The swap. NO explicit signOut first: signInWithCredential replaces the
    // session on success; on failure the anon shell MUST survive (#414/#213).
    // NO cleanup-intent, NO _cleanupWithInlineRetry — the post-gate shell is
    // provably empty (PR2 gates fcm + drops recoveryCleanupIntents).
    final result = await _auth.signInWithCredential(googleCredential);
    FirebaseConfig.log('Restore: restored uid ${result.user?.uid}');
    return result;
  } finally {
    await _safeClearRecoveryOpState();
    await _cacheIsolationController.restart();
  }
}
```

**Ordering invariants (each is a test):**
- `_removeFcmToken()` runs **before** `engageIsolation()` and before the swap (owner-only rule + provider-invalidation).
- credential obtained **before** `engageIsolation()` (cancel-safe; no overlay strand).
- `markFirestorePersistenceDirty(_prefs)` is **awaited** and precedes the swap.
- NO `signOut()` anywhere in the path.
- NO `cleanupAnonUidArtifacts` / `recoveryCleanupIntents` / `_cleanupWithInlineRetry` call (assert the merge seams are never touched).
- `restart()` runs in `finally` on **both** success and a thrown swap.

### `_removeFcmToken` seam

`AuthRecoveryService` has no `NotificationService` dependency today. Add a constructor seam mirroring `googleCredentialFactory`:

```dart
typedef FcmTokenRemover = Future<void> Function();
// ctor param: FcmTokenRemover? removeFcmToken
// field default when null: () async {}   // no-op (tests inject a recorder)
```

Wire the real remover in `authRecoveryServiceProvider` (`auth_provider.dart:60-68`):
```dart
removeFcmToken: () => ref.read(notificationServiceProvider).removeToken(),
```
Resolved lazily at call time, **before** `engageIsolation()` invalidates `notificationServiceProvider`.

## Conflict classifier (for PR2's gate)

`restoreWithGoogle`'s own `signInWithCredential` never throws `*-already-in-use` (that is link-only). The classifier exists for PR2: when the gate's `linkGoogleToCurrentUser()` (`:272`) throws, PR2 calls this to decide "offer switch-to-existing-account → `restoreWithGoogle(credential: <reused>)`".

```dart
/// True when a LINK attempt failed because the Google account already backs a
/// different Firebase user. One-account-per-email surfaces EITHER code; never
/// trust FirebaseAuthException.credential (nullable — flutterfire #9920), so we
/// branch on the code alone and the caller re-obtains/reuses the credential.
bool isGoogleAccountAlreadyInUse(Object error) =>
    error is FirebaseAuthException &&
    (error.code == 'credential-already-in-use' ||
     error.code == 'email-already-in-use');
```
Table-driven test: both codes → true; other codes → false; non-`FirebaseAuthException` → false. (Ship as a top-level function or static; do **not** read `.credential`.)

## Restore entry (home empty-state CTA — repoint, no new route)

The single PR3 entry keeps its existing `BuildContext`; the restore is an async action (Credential Manager is its own consent — no extra app dialog). On success the swap restarts the app (never returns to UI); on cancel it is silent; on real error it shows a snackbar.

Shared helper (new, tiny — `lib/features/auth/widgets/google_restore_action.dart`), so PR2's gate-conflict path and a future PR3b/Profile entry can reuse it:
```dart
Future<void> triggerGoogleRestore(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authRecoveryServiceProvider).restoreWithGoogle();
    // success path restarts the app; nothing to do here
  } on GoogleSignInException catch (e) {
    // user dismissed the Credential Manager sheet — silent (no swap happened;
    // restoreWithGoogle obtains the credential BEFORE engaging isolation, so a
    // cancel leaves the anon shell fully intact).
    if (e.code == GoogleSignInExceptionCode.canceled) return;
    if (!context.mounted) return;
    _snack(context, context.l10n.restoreGoogleFailed);
  } catch (_) {
    if (!context.mounted) return;
    _snack(context, context.l10n.restoreGoogleFailed);
  }
}
```
- **Cancel handling (Gate R1 [P2]):** the plugin surfaces a user-dismiss as `GoogleSignInException(code: GoogleSignInExceptionCode.canceled)` (verified `google_sign_in_platform_interface/lib/src/types.dart`), NOT a custom exception. Branch on that code for the silent path; pin the exact type in a test. (There is no `RestoreCancelledException` in the codebase — do not invent one.)
- **Snackbar (Gate R1 [P2]):** there is **no** `showAppSnackBar` util. Use `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`. `darkTheme` now sets `snackBarTheme` with `behavior: floating` (`app_theme.dart:221-230`, commit `9bcddaad`/#419), so a per-call `behavior` override is **not** required (Gate R2 [P3]). No `action` ⇒ no `persist:true` trap. Encapsulate as a file-private `_snack(BuildContext, String)` in `google_restore_action.dart` (mirrors `profile_screen.dart`'s private `_showSnack`).
- **Home** (`home_screen.dart:312-322`): keep `Key('home_empty_recover_cta')` (at `:312`); `onPressed: () => triggerGoogleRestore(context, ref)` (replaces `context.push('/recover')` at `:313`; `_DashboardContentState` is a `ConsumerState`, `ref` in scope). Update the label to a Google-aware string (new key `homeRestoreWithGoogle`, EN+AR); the old `homeRecover` key is left in the ARB (no other `lib/` caller — verify with grep) and retired from use.

**`GoogleSignInGateway.obtainCredential()` errors** also include `StateError` (missing serverClientId/idToken) — these fall to the generic `catch` → snackbar, correctly (they are real config errors, not cancels).

## The 7 verification principles (run against live code in `../Rihla-441-pr3`)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).** The new write is `signInWithCredential` (auth, not Firestore) + the durable `markFirestorePersistenceDirty` prefs write (OUTBOUND, read by `CacheUidBarrier.reconcile` on the next cold boot) + `removeToken()` delete (OUTBOUND). No money/ledger write path is touched. The one repointed entry is UI-only (was a route push). `_googleCredentialFactory` is reused unchanged (no new persisted shape).
2. **Every concrete claim verified against code (not docs/agent citations).** Re-read in-session: `auth_recovery_service.dart:51-102` (ctor seams + `_googleCredentialFactory`), `:294-386` (`completeRecovery` template), `:498-526` (`signOutCurrentDevice`), `:272-281` (`linkGoogleToCurrentUser`); `auth_provider.dart:60-68` (`authRecoveryServiceProvider` wiring); `home_screen.dart:312-313` (CTA key + push); `notification_service.dart:274-288` (`removeToken`, never rethrows). Confirmed at impl (Gate R1): `notificationServiceProvider` symbol/path; **no `showAppSnackBar`** util exists → use `ScaffoldMessenger…floating` via a private `_snack`; `google_sign_in` 7.x cancel surfaces as `GoogleSignInException(code: GoogleSignInExceptionCode.canceled)` (no custom exception).
3. **One read-path per write-path.** `markFirestorePersistenceDirty` → read by `CacheUidBarrier.reconcile` (`firebase_config.dart` `_runCacheBarrier`) on cold boot → `clearPersistence`. `signInWithCredential` → `authUserChangesProvider`/`uidProvider`/`linkedEmailProvider` re-emit; but the **overlay is engaged**, so no live screen reads them until the true restart re-mounts the app on the durable UID. `removeToken` delete → no reader (the doc is shell residue).
4. **Fields enumerated from the type.** No new persisted Firestore shape. `restoreWithGoogle` returns `UserCredential` (mirrors `completeRecovery`). The injected seams are 2 typedefs (`FcmTokenRemover`, reused `GoogleCredentialFactory`).
5. **Data contracts spelled out.** `restoreWithGoogle({AuthCredential? credential, Duration pendingWritesTimeout})→Future<UserCredential>`; `isGoogleAccountAlreadyInUse(Object)→bool`; `FcmTokenRemover = Future<void> Function()`; `triggerGoogleRestore(BuildContext, WidgetRef)→Future<void>`. Provider wiring adds exactly one ctor arg.
6. **Arithmetic decomposition.** N/A — no balance/aggregate math touched. (Explicitly: PR3 does not read or write any `BalanceCalculator`/`MoneySerializer`/aggregate surface.)
7. **Adversarial pass on an orthogonal axis (identity).** The fix is on the *auth-swap* axis; the adversarial worked example exercises **identity orphaning** (axis B): a user with a *non-empty* anon shell taps restore → `signInWithCredential` orphans their local data under the old UID. **Resolved (Gate R1 [P1]):** the only PR3 entry — the home CTA — renders **exclusively** on `groups.isEmpty` (`home_screen.dart:96-97` → `_buildEmpty:245`), so a shell that can reach it has zero groups → zero money data → nothing to orphan. The originally-planned Profile `_PendingRecoveryBanner` repoint, which has **no** empty-shell guard (renders on `pendingEmailLinkProvider != null`, `:258`), is therefore **dropped from PR3** — that is the data-loss path, and it is also the wrong flow (email banner → Google sheet). Second identity probe: a **cancelled** Google sheet must leave the anon UID signed-in and untouched — guaranteed because the credential is obtained *before* `engageIsolation` (no swap, no restart, no overlay on cancel). Third: a **failed** swap (network) must return to the *same* anon UID after restart (no `signOut`, `#414` discipline) — the markDirty-induced cache clear is a benign cache miss, not data loss.

## TDD plan (RED first)

**Unit — `test/unit/auth_recovery_service_google_restore_test.dart` (new):**
- RED: ordering — record calls on injected fakes (recording `CacheIsolationController`, recording `FcmTokenRemover`, mocktail `FirebaseAuth` whose `signInWithCredential` returns a fake `UserCredential`, recording `GoogleCredentialFactory`). Assert sequence: `removeFcmToken` → `engageIsolation` → `markFirestorePersistenceDirty` (prefs bool set) → `signInWithCredential` → `restart`. Assert credential obtained before `engageIsolation`.
- `signInWithCredential` throws → `restart` still called (finally), exception propagates, **no** `signOut`.
- credential factory throws (cancel) → **no** `engageIsolation`, **no** `restart`, **no** `removeFcmToken`-after, anon shell untouched, exception propagates.
- `restoreWithGoogle(credential: x)` uses `x`, does **not** call the factory (PR2 reuse path).
- Assert the merge seams (`cleanupAnonUidArtifacts`, `cleanupIntentFactory`) are **never** invoked.
- `markFirestorePersistenceDirty` awaited before the swap (prefs flag true at swap time — assert via a recording prefs/order check).
- waitForPendingWrites timeout → swallowed, swap still proceeds.

**Unit — classifier (`..._conflict_classifier_test.dart` or in the same file):** table: `credential-already-in-use`→true, `email-already-in-use`→true, `wrong-password`→false, `StateError`→false, plain `Exception`→false. Assert `.credential` never read (construct a `FirebaseAuthException` with `credential: null` and the in-use code → still true).

**Widget — `test/features/home/home_restore_cta_test.dart` (new, none exists):** override `authRecoveryServiceProvider` with a recording fake; pump empty-state; tap `home_empty_recover_cta`; assert `restoreWithGoogle` called; assert it does **not** `context.push('/recover')` (no nav). Override `sharedPreferencesProvider`; do **not** `pumpAndSettle` (ConnectivityNotifier Timer). Mirror existing home test boot helper. Add a cancel case: the fake throws `GoogleSignInException(canceled)` → no snackbar shown; an error case: throws `StateError` → snackbar shown.

**Guard:** grep `test/` for `home_empty_recover_cta` / `homeRecover` / `'/recover'` before editing — the route-tree test (`app_router_test.dart:90-91`) must stay green (PR3 keeps the `/recover` route). The Profile screen is **untouched** by PR3 (no banner repoint), so its existing tests stay green unchanged.

## Coordination with the concurrent PR2 session

- PR3 ships `restoreWithGoogle` + `isGoogleAccountAlreadyInUse` as the gate-conflict resolution API; **PR2 consumes** them (detect link failure → classify → `restoreWithGoogle(credential: reused)`). Flag this in the PR body so PR2 wires it.
- Keep edits additive; do **not** touch the gate (`createGroup`/`joinGroup`), the sign-in sheet, FCM `!isAnonymous` write-gating, or `firestore.rules` (all PR2). PR3 only *relies on* the owner-only fcm rule, doesn't change it.
- Merge **after** PR2; rebase onto main once PR1 lands.

## Files touched (estimate)

- `lib/features/auth/services/auth_recovery_service.dart` — add `restoreWithGoogle`, `FcmTokenRemover` seam, `isGoogleAccountAlreadyInUse` (or a sibling file).
- `lib/features/auth/providers/auth_provider.dart` — wire `removeFcmToken` into `authRecoveryServiceProvider` (+ import `notificationServiceProvider`).
- `lib/features/auth/widgets/google_restore_action.dart` — new `triggerGoogleRestore` helper + private `_snack`.
- `lib/features/home/screens/home_screen.dart` — repoint CTA onPressed + label.
- `lib/l10n/app_en.arb` + `app_ar.arb` — `homeRestoreWithGoogle`, `restoreGoogleFailed`.
- Tests as above.
- **Commit the parent epic plan** `docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md` + **this spec** to the branch (Gate R1 [P3] — both are untracked in main; a reviewer/implementer on this branch must be able to read the scope decisions).

**NOT touched:** `lib/features/settings/screens/profile_screen.dart` (no banner repoint — note the file is under `settings/screens/`, NOT `lib/features/profile/`), Firestore rules, Cloud Functions, money/aggregate, router tree, no new GoRoute.
