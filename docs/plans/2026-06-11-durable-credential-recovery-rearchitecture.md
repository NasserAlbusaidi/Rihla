# Durable-credential recovery re-architecture (kill the cross-UID merge)

**Status:** DECIDED 2026-06-11 — supersedes the email-link RECOVER half of `docs/ACCOUNT-RECOVERY.md`.
**Decision owner:** Nasser. **Verified:** 7-agent code verification + adversarial skeptic, 2026-06-11 (all citations below re-checked against live code, not docs/memory).

## Root cause (verified)

Money data is born under a throwaway anon UID; every ledger reference (`payerParticipantId`, `splitDistribution` keys, `participantIds`, `memberIds`, settlement parties, member-doc `userId`) is keyed to that raw UID. Reclaiming it on a durable identity therefore demands a cross-UID swap + server rewrite — `cleanupAnonUidArtifacts` (691 LOC) — which generated #213/#216/#414/#427.

The asymmetry that makes the fix cheap:

- **LINK half is already same-UID:** `completeEmailLink` → `user.linkWithCredential` (`auth_recovery_service.dart:239`). Zero migration, zero cache machinery. Never caused a bug.
- **RECOVER half is the swap:** `completeRecovery` → `signInWithEmailLink` (`auth_recovery_service.dart:316`) → `recoveryCleanupIntents/{oldUid}` intent doc → `cleanupAnonUidArtifacts` callable → forced restart. This is the entire bug class.

We are not fixing recovery; we are deleting the swap. **Durable credential (Google) is required before the first valuable write (create/join group); recovery on a new device = `signInWithCredential` → same UID → everything loads.**

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Anon-on-first-launch stays; **gate at first create/join**, not at launch | Zero-friction browse kept; reuses the #288/#352 natural-moment pattern |
| D2 | Gate credential = **Google** (Credential Manager sheet via google_sign_in 7.x) | Ubiquitous on Play-distributed Android; survives offline after first link. NOT phone-OTP (dead-zone road trips). Apple added when iOS un-defers (App Store 4.8) |
| D3 | **Slim email fallback kept** (decided over Google-only) | `linkWithCredential` alone is decorative — getting back in needs a sign-in path. Keep `sendSignInLink` + a **no-merge** `signInWithEmailLink` that discards the provably-empty shell via the same isolation+restart protocol as Google. Optional to set up; prevents Google-loss = permanent money lockout |
| D4 | **Delete the merge engine** (~4,500 LOC inventory below) | Shells are empty by construction post-gate; the merge has no remaining job |
| D5 | **Cache-isolation stack is MUST-KEEP** — Opus's "conditionally retire" clause is struck | Deletion/sign-out *are* the stack (`data_deletion_service.dart:77-88` has no independent cache clear; in-session `clearPersistence` throws — `firestore_cache_gate.dart:11-15`); the every-boot anon mint (`firebase_config.dart:115-118`) keeps the cold-boot barrier permanent; and this plan **adds two new in-session UID swaps** (discard-shell, restore-on-device-with-live-anon) that must run engage→dirty→swap→restart or they reopen #45/#68 |
| D6 | Option D (same-UID custom-token seed phrase) **dropped** | Offline cost of the gate is ~zero (verified below); D solves a problem that doesn't survive verification |
| D7 | Zero migration — exploit "no real users yet" | But see the mechanical prod check gating PR5 |

## Verified facts the plan stands on

- **Join is already hard-online:** exclusively the `joinGroupByInviteCode` callable (`group_provider.dart:224-226`). Nothing offline is lost by gating it.
- **Offline group-create is not a real capability today:** brand-new users can't boot offline at all (anon mint needs network, `_AuthGate` retry splash `main.dart:162-172`); a previously-launched anon user creating offline hits the 15s timeout (`create_group_screen.dart:97`) → error snackbar, member doc never issued until reconnect; create/join screens have zero OfflineBanner wiring; **no test pins offline create**.
- **Post-gate, the offline money pipeline is untouched:** no write path reads `isAnonymous`; linking preserves the UID; all 5 expense/settlement sites keep `awaitServerAck`+`noteQueuedWrite` semantics.
- **Pre-gate anon shell writes are exactly two:** `fcm_tokens/{uid}` (reachable pre-group via the Profile toggle `profile_screen.dart:735` + boot listener `app_bootstrap_provider.dart:22,36`) and `recoveryCleanupIntents/{oldUid}` (deleted by this plan). Server-managed throttle residue (`joinAttempts` etc.) is client-denied throwaway. With FCM gated, the shell is **provably empty** → discard-shell is safe.
- **UID swappers post-change:** boot anon mint (made harmless by durable credential, but barrier stays), account deletion, sign-out, + the two NEW swaps this plan introduces. `recoverRestoredSessionIfNeeded` (#213) confirmed structurally non-destructive.
- **No Google sign-in surface exists today:** no plugin, no `GoogleAuthProvider`/`signInWithCredential` anywhere in `lib/`, no gms Gradle plugin (Dart-only Firebase init, `android/app/build.gradle.kts:4-8`).

## Mandatory mitigations (spec-level requirements, not nice-to-haves)

1. **Server-enforce the gate.** Rules predicate `request.auth.token.firebase.sign_in_provider != 'anonymous'` on group create (+ the batched `inviteCodes` create), and an anonymous-provider reject in `joinGroupByInviteCode` (auth check exists at `:226`, no provider check). Without this, the no-merge world's safety invariant ("no valuable data is ever anon-keyed") is a client promise; any ungated client (incl. the live v1.3.x/v1.4.0 Play build) mints anon-owned groups into a world with **no recovery path and no merge engine** — strictly worse than today. ~3 lines of rules.
2. **Gate placement: inside `GroupService.createGroup` before batch staging** (`group_provider.dart:120`), not at UI/navigation level — an offline-queued batch replays on reconnect and bypasses UI gates. Symmetrically before the callable in `joinGroup` (`:191`).
3. **FCM shell-emptiness:** gate `fcm_tokens/{uid}` writes on `!isAnonymous` (push only matters to group members, who are credentialed post-gate; the #288 natural-moment fires post-create/join so it survives). In the discard-shell branch, `removeToken()` **before** the swap — owner-only rules (`firestore.rules:171-173`) make the old UID's token doc permanently un-deletable afterwards.
4. **Both new swaps run the full isolation protocol:** discard-shell and restore-on-populated-device go through engageIsolation → `markFirestorePersistenceDirty` → swap → true restart (the existing `PlatformCacheIsolationController` machinery).
5. **Intent persistence across the restart:** the invite code (deep-link auto-submit, `join_group_screen.dart:226`) or create-group form state must survive the forced restart so the user lands back in the flow.
6. **Conflict branch robustness:** handle BOTH `credential-already-in-use` AND `email-already-in-use` (one-account-per-email can surface either); never trust `FirebaseAuthException.credential` (can be null — flutterfire #9920); reuse the original Google credential or re-run `authenticate()`.
7. **PR5 (deletion) gated on a mechanical prod check:** query prod for groups whose `memberIds` contain an anonymous-provider-only UID. Zero hits required. "No real users" is a decision, not a fact — re-verify at deletion time.
8. **google_sign_in 7.x reality:** Credential Manager sheet ("one-tap" legacy API is gone); Dart-only init means no `default_web_client_id` resource — pass `serverClientId` explicitly via the existing `config.json` dart-define mechanism (decided: keep Dart-only init, don't adopt the gms plugin). External console steps that fail silently: enable Google provider; register SHA-1/256 for **debug keystore + CI upload key + Play App Signing key** (Play re-signs AABs — missing the last one means sign-in works in every local/CI build and fails for every Play install).

## PR sequence

| PR | Scope | Gate? |
|---|---|---|
| PR1 | google_sign_in 7.x dep + `linkGoogleToCurrentUser()` in `AuthRecoveryService` (mirrors `:239`) + `serverClientId` via config.json + console setup (external). No behavior change | exempt (no wiring) |
| PR2 | The gate: inside `createGroup`/`joinGroup` + sign-in sheet UI; FCM `!isAnonymous` gating; **rules predicate + callable anon-reject** | **Gate-category** (rules + functions) → `/run-the-gate` |
| PR3 | Restore: `signInWithCredential` entries (home empty state + Profile), discard-shell branch through the full isolation protocol, conflict handling, intent persistence across restart | **Gate-category** (auth swap paths) |
| PR4 | Slim email fallback: keep `sendSignInLink`; replace `completeRecovery` with a no-merge `signInWithEmailLink` discard-empty-shell path; delete `MergeOnRecoverDialog` semantics | Gate-category (auth) |
| PR5 | Delete the merge engine + ops tail + `ACCOUNT-RECOVERY.md` rewrite; deploy-ceremony (`firebase functions:delete cleanupAnonUidArtifacts`, drop the `recoveryCleanupIntents` TTL fieldOverride `firestore.indexes.json:67-76`, sweep residual intent docs) | Gate-category (rules + functions) + prod check (mitigation 7) |

Ordering: PR5 last, only after PR3 is device-QA'd. The merge engine coexists harmlessly until then.

## Deletion inventory (PR5)

Fully deletable: `functions/src/callables/cleanupAnonUidArtifacts.ts` (691) + test (1125), `recover_screen.dart` (221), `recover_pending_screen.dart` (272), `merge_on_recover_dialog.dart` (65), `firebase_functions_service_cleanup_outcome_test.dart` (114), `recover_screen_test.dart` (275), `recover_pending_screen_test.dart` (246), `auth_recovery_service_restart_guarantee_test.dart` (101).
Partial edits: `auth_recovery_service.dart` ~380/490 (keep link path + `signOutCurrentDevice`), `firebase_functions_service.dart` ~35/88, bootstrap `opRecover` branch, `app_router.dart` `/recover` routes (PR4 may repoint instead of delete), rules `:230-255` (`validCleanupIntent` + `recoveryCleanupIntents` block), `index.ts:7`, ARB ~120, mixed tests ~715.
**NOT deletable (shared):** the entire cache-isolation stack (7 pieces), `deletionReaper.ts`, the email LINK path, `firebase_auth_test.dart` (#213 contract).
Total ≈ **4,500 LOC**.

## New UI

- **Gate sheet** at create/join: "Keep your account safe" — one-tap Google (Credential Manager), reuses #352 rationale-sheet + #288 natural-moment patterns. Blocking (write proceeds only after link), with a clear "why" line.
- **Restore entry**: "Sign in with Google" on home empty state (replaces the `/recover` push at `home_screen.dart:313`) + Profile account section.
- **Conflict dialog**: "This Google account already has Rihla data — switch to it?" → discard-shell + restart.
- **Profile account section rework**: Google account row (linked state, avatar/email) + optional email fallback row; `account_backup_nudge` repointed at Google link.
- **Deleted**: RecoverScreen, RecoverPendingScreen, MergeOnRecoverDialog.

## In-flight work re-scoped (2026-06-11)

- **#428** re-scoped → restore entry points for the NEW flow (PR3); its old scope built entries into the deleted `/recover` path.
- **#431** closed superseded — `_cleanupWithInlineRetry` is deleted in PR5.
- **#414 NS-45 device retest** dropped — tests a deleted path.
- **PR #430** (merged 2026-06-10): its device-QA gate is moot; sunk cost accepted.

## Rejected alternatives

- **A (keep hardening the swap):** keeps the whole bug class open.
- **B (durable identity from launch):** login wall contradicts zero-friction browse.
- **D (same-UID custom-token seed phrase):** solved an offline cost that verification showed doesn't exist; weaker UX.
- **E (group-anchored re-join):** is the cross-UID merge with a name-claim hole added.
- **Google-only (no email fallback):** Google-loss = permanent money lockout; rejected in favor of D3.
