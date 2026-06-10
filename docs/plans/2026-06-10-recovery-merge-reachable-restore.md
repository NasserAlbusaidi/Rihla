# Recovery: Merge-on-Restore + Reachable Restore — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make account recovery (a) reachable once a device already has groups, and (b) *merge* this device's data into the restored account instead of signing out and orphaning it.

**Architecture:** The server callable `cleanupAnonUidArtifacts` *already* performs a conserving `oldUid → newUid` migration (sum-merge on money keys, dedupe on id arrays, member-doc copy/delete by `userId` field). `completeRecovery` already invokes it with the current anon UID, **awaits it to completion inside the cache-isolation overlay before the restart**, and never signs out (#414). The only thing defeating the merge is `RecoverScreen._confirmIfDevicePopulated()`, which signs the populated UID out *before* the link is sent — and no in-session re-mint exists (anon mint happens only at boot, `firebase_config.dart:115-118`), so by `completeRecovery` time `oldUid` is either **null** (app stayed warm until the link tap: `currentUser` is null → the cleanup block is skipped entirely) or **a fresh empty UID** (the deep link cold-started the app and boot minted a new anon). Both sub-paths orphan everything under the signed-out UID. We remove that sign-out (turning the populated path into a consented merge), make the cleanup result visible and **retry a partial cleanup inline (still inside the overlay, before restart)** instead of silently swallowing it, and add reachable Restore entry points. No server/rules changes — the migration machinery is reused as-is.

**Tech Stack:** Flutter, Riverpod 2.x, Firebase Auth (anon + email-link), Cloud Functions (existing `cleanupAnonUidArtifacts`), SharedPreferences, `mocktail` + `firebase_auth_mocks` + `FakeFirebaseFirestore`.

**Sequencing (two PRs, land in order):**
- **PR-B (lands FIRST): Merge instead of orphan — `Closes #427`** — Tasks 1–5. Makes the populated recover path a correct, consented merge with inline partial-failure retry + loud surfacing. Safe to land alone: the populated path stays reachable only via the existing dangling-link banner (verified: `_PendingRecoveryBanner` renders only when `pendingEmailLinkProvider != null`, set solely by the bootstrap at `auth_email_link_bootstrap_provider.dart:139` when a link arrives with no primed pending email), so no *new* orphan exposure is created.
- **PR-A (lands SECOND): Reachable Restore — `Closes #428`** — Tasks 6–8. Adds intentional Restore entry points now that reaching them performs a correct merge. Must NOT precede PR-B (a reachable entry over the old sign-out path would make the orphan bug *more* reachable). **Gated on the P2-1 device-QA check below.**

(No pre-existing issues covered either PR — #414 is CLOSED and scoped to the link-conflict auto-fallback fix only. #427/#428 filed 2026-06-10.)

**Out of scope (#429):** the user-reported "Linked email: not set after a completed Android restore". Evidence says recovery's auth swap succeeds (UID `HIvg…` last-login matches today) and `cleanupAnonUidArtifacts` ran; the live "Tge Boys" group was scrubbed by a **Delete-Account** at the same minute (`deletionAttempts/zh0Jf…`, `createdBy:"deleted-user"`), not a recovery failure. Filed as #429; investigate on-device only if it reproduces after PR-B. **BUT** the cold-boot guarantee that the *email-linked* session (not a fresh anon) is restored is load-bearing for merge — covered by Task 5's regression test + the P2-1 device-QA gate, NOT deferred.

---

## Gate round 1 — applied
A fresh-context Opus Gate (3 P1, 3 P2, 3 P3) reviewed the prior draft. Applied: **P1-1/P1-3** — replaced the cold-boot retry (faulty: 15-min `oldUid`-bound intent can't be recreated by a `newUid` caller; ran with no overlay against a live router) with an **inline retry inside `completeRecovery`** (overlay up, pre-restart, seconds after intent creation → intent still valid, no live read). **P1-2** — added the `cascadeFailed` worked example + residual-stranding bound. **P2-1** — added Task 5 regression + a device-QA gate before PR-A. **P2-2** — Task 1 lands the typedef change + `completeRecovery` consumption atomically. **P2-3/P3s** — folded into task notes.

## Gate round 2 — PASS (0 P1), applied 2026-06-10
Re-run as a fan-out: 4 claim-verifiers (23 concrete claims re-checked against live code: 14 CONFIRMED, 8 PARTIAL-corrected, 1 WRONG-corrected) + **two fresh-context Opus reviewers** (identity/partial-failure lens; money/test-executability lens). **Both verdicts PASS — zero P1s.** Applied below: **[P2]** the `Future<void>→Future<CleanupOutcome>` typedef change breaks two test files the draft never named (`auth_recovery_service_restart_guarantee_test.dart:67`, `auth_recovery_service_inflight_op_test.dart:64`) — added to Task 1's atomic set. **[P3s]** lost-response retry fires a false Sentry alarm (intent already consumed by a server-side success) → permission-denied-on-retry handled as success-equivalent + new test case (worked example 3); Step 5's swallow-vs-rethrow pinned (never rethrow; `return result` contract preserved); two existing always-throw cleanup tests now see two invocations → updated; Task 3's dirty-marking test is *deleted* not inverted; claim corrections folded into the principles below (client timeout is 60s not ~70s; `_allocateExact` cite; soft-deleted-events nuance; Task 5's real test file; ACCOUNT-RECOVERY.md has two more stale spots; FR-REC defs live only in a deleted doc; #366 aggregate read-path note).

---

## Verification principles (run against live code — reported out loud per the Operating Contract)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).**
   - `firebase_functions_service.dart:cleanupAnonUidArtifacts` — **OUTBOUND** (drives the server migration). Currently `Future<void>`, discards `cascadeFailed` → the swallow.
   - `RecoverScreen._confirmIfDevicePopulated` `signOut()` — **OUTBOUND side-effect** (mints a fresh anon UID). Removing it is the crux.
   - the inline retry in `completeRecovery` — **OUTBOUND** (re-drives the idempotent migration).
   - `linkedEmailProvider` read in profile/home — **INBOUND** (display only).
2. **Concrete claims verified against code (not docs), this session:** `firebase_functions_service.dart:18-26` returns `Future<void>`, never reads `.data` (confirmed). `completeRecovery` (`auth_recovery_service.dart:256-359`) sets `oldUid = current anon uid`, creates the intent (`:285`), engages the overlay (`:274`), `signInWithEmailLink` (`:315`), `await`s `cleanupAnonUidArtifacts(oldUid)` (`:331`) — no `signOut` (confirmed, #414). The server completes the scrub even if the client restarts mid-await — gen2 onCall is not aborted by client disconnect (`:326-329` comment). `_confirmIfDevicePopulated` (`recover_screen.dart:47-67`) calls `signOut()` + off-table `markFirestorePersistenceDirty` (confirmed). Entry points: only `home_screen.dart:313` (empty-state) and `profile_screen.dart:272` (pending-link banner) reach `/recover` (confirmed). Intent write rule (`firestore.rules:234`): `recoveryCleanupIntents/{oldUid}` requires `request.auth.uid == oldUid` — so it can only be written before the sign-in swap; a `newUid` caller CANNOT recreate it (confirmed — this is why retry must be inline, pre-swap-invalidation, within the 15-min `cleanupIntentMaxAgeMs`). The server **consumes (deletes) the intent only on full success** (`cleanupAnonUidArtifacts.ts:668-680` — auth-delete + intent-delete both gated on `cascadeFailed.length === 0`), so a structured partial failure leaves the intent in place for the inline retry. Stale figure fixed in round 2: the `completeRecovery` comment's "~70s client timeout" (`auth_recovery_service.dart:326`) is actually **60s** — no `HttpsCallableOptions` anywhere in `lib/`, and FlutterFire's default is 60s (`cloud_functions_platform_interface` 5.8.12); fix the comment while Task 1 touches that block. A client deadline-exceeded does NOT mean the server failed — the server runs to `timeoutSeconds: 540` regardless, so a retry can overlap a still-running first invocation; the oldUid-key-gated sum-merge makes that overlap convergent.
3. **Read-path per write-path:** the merge writes `groups.memberIds: oldUid→newUid`. Reader: `userGroupsProvider` (`group_provider.dart:439-445` → `watchUserGroups:366-377`, `groups where memberIds array-contains current uid`); after restart current uid = newUid → migrated groups appear. **A group whose migration FAILS keeps `memberIds:[oldUid]` → it does NOT match newUid → it vanishes from the user's groups and its debt drops from `homeGroupBalanceProvider`** (this is P1-2; see worked example #2). **#366 aggregate note (post-#424):** `homeGroupBalanceProvider` prefers the server aggregate (`groups/{gid}/aggregates/balance`, `netMilli` keyed by uid) when online. `cleanupAnonUidArtifacts` does NOT rewrite aggregate docs — the oldUid-keyed `netMilli` entries converge *indirectly* when the `balanceAggregator` triggers fire on the cleanup's own expense/settlement writes (+ the scheduled reconciler). Post-restart home display may briefly show stale aggregate state until the triggers settle — eventual-consistent display lag, NOT a conservation bug, and no plan change needed; named here so it isn't misread as a failed merge during device-QA.
4. **Fields enumerated from the migration source (`cleanupAnonUidArtifacts.ts`):** `groups.memberIds`, `groups.createdBy`, member docs (by `userId` field, copy-if-absent keyed `.doc(newUid)` + delete-all-`userId==oldUid`), `events.participantIds`, `events.participantNames` (a **key rename** `oldUid→newUid` preserving the display-name string; on collision OLD's name overwrites NEW's — display-only), `events.createdBy`, `expenses.createdBy/payerParticipantId/customSplitParticipants/splitDistribution`, event+group `settlements.payerParticipantId/recipientParticipantId/createdBy`, `activity_logs.actorId/targetParticipantId(event-scoped only)/metadata`, plus bookkeeping `updatedAt` on events/groups. **Soft-delete nuance (round-2 fix):** soft-deleted *expenses* are skipped (`:406-408`); soft-deleted *events* are NOT fully skipped — the events loop migrates `participantIds`/`participantNames` on ALL events including soft-deleted (`:369-385`), only `events.createdBy` is gated on `isDeleted !== true` (`:386`), and child collections (expenses/settlements/activity_logs) are fetched for active events only (`:345-358`).
5. **Data contracts (exact):**
   - callable input `{ oldUid: string, cleanupSecret: string }`; output `{ groupsProcessed: number, cascadeFailed: string[], authUserDeleted: bool, fcmTokenDeleted: bool, joinAttemptsDeleted: bool }`.
   - new wrapper return `CleanupOutcome { List<String> cascadeFailed; bool get complete => cascadeFailed.isEmpty; }`.
   - `CleanupAnonUidArtifacts` typedef → `Future<CleanupOutcome> Function({required String oldUid, required String cleanupSecret})`.
   - merge-consent dialog returns `Future<bool?>` (true = proceed).
   - **No prefs marker** (the cold-boot retry was removed in Gate round 1).
6. **Arithmetic decomposition:** `mergeUidMapKey` (`cleanupAnonUidArtifacts.ts:147-170`) deletes `oldUid` and SUMs its persisted integer subunits onto `newUid` (`next[newUid] = subunits(old) + subunits(new)`; `toFiniteNumber` — **TS-side only**, `:133-135` — zeroes a forged non-numeric in that sum). `sum(values)` is invariant → `sum(shares) == amount` holds; no allocator re-runs (the persisted map is edited in place), so the alphabetically-last-remainder contract is untouched. On the Dart read side, `_allocateExact` (`expense_provider.dart:489-553` — round-2 cite fix) rejects negatives via the `:501-504` guard (→ equal-split fallback), re-validates total vs tolerance at `:511-514`, and closes any in-tolerance residual non-negatively (`:533-548`). Verified for exact (subunits), percent (1000×), shares (raw int) — all linear sums.
7. **Adversarial pass on an ORTHOGONAL axis:** the fix is **identity** (oldUid→newUid). Worked examples below exercise **money** (both-members exact sum-merge), **settlements** (oldUid-paid/newUid-received → self-settlement), and **the partial-failure axis** (a group that fails to migrate).

### Worked example 1 — all-success (money + settlement axes)
Device anon `OLD` has group **Trip** (also containing the to-be-restored email account `NEW` as a joined member):
- Expense `e1` (`exact`): `splitDistribution = { OLD:500, NEW:300, C:200 }` (subunits, amount 1000) → after merge `{ NEW:800, C:200 }`. Sum 1000, tolerance passes, no negative. ✅
- Settlement `s1`: `payer=OLD, recipient=NEW, 400` → `payer=NEW, recipient=NEW` self-settlement, nets to 0. Inert. ✅ (Verified in `calculateBalances`: the payer and recipient branches are independent ifs over the same `settlementAdjustmentMap` (`expense_provider.dart:421-434`) — both fire on key NEW, `+400 − 400 = 0`; neither dropped nor distorting.)
- `Trip.memberIds = [OLD,NEW]` → `[NEW]` (dedupe); `OLD` member doc deleted, `NEW`'s retained. ✅
Post-restart uid = `NEW`; `userGroupsProvider` shows **Trip** + the restored account's other groups. ✅

### Worked example 2 — partial failure (the P1-2 axis)
`OLD` is in **Trip** and **Souq**. The callable's per-group try/catch (`cleanupAnonUidArtifacts.ts:595-616`) succeeds for Trip, throws for Souq → `cascadeFailed:['Souq']`, server KEEPS the `OLD` Auth user + intent (`:668-680` — both deletes gated on `cascadeFailed.length === 0`). Without handling: after restart (uid=`NEW`) **Souq vanishes** (its `memberIds` still `[OLD]`) and its debt silently drops from the home hero — a money-correctness gap, not inert. **Handling (Task 1):** `completeRecovery` sees `!outcome.complete`, retries the (idempotent) callable ONCE inline — still inside the overlay, intent still valid (seconds old, AND not consumed: consumption only happens on full success) → Souq converges. If the retry still fails, record a **Sentry error** with `cascadeFailed`, then restart; the residual is: Souq stays under `OLD` (Auth user KEPT, recoverable) but is invisible to `NEW` and unfixable once the 15-min intent expires. **Accepted bound (no real users yet); loud-logged, not silent.**

### Worked example 3 — lost-response retry (the false-alarm axis, Gate round 2)
The first call **throws client-side** (60s client timeout / dropped response) but the server — which runs to `timeoutSeconds: 540` regardless of client disconnect — **fully succeeded**: it deleted the `OLD` Auth user AND consumed the intent (`:668-680`). The inline retry then hits `assertCleanupIntent` (`:289-291`) → no intent → `HttpsError('permission-denied')`. Naively recording that as a cleanup failure files a **false Sentry alarm for a migration that succeeded**. **Handling (Task 1):** when the *first attempt threw* (no structured outcome) and the retry throws `FirebaseFunctionsException` with code `permission-denied`, treat it as **success-equivalent** (intent consumed by a completed first invocation) — breadcrumb, NOT the error recorder. Scope matters: on the *structured-partial* first path (`cascadeFailed` returned), the server provably kept the intent, so `permission-denied` on that retry is a genuine anomaly and DOES record. Either way recovery returns the credential and the `finally` restarts.

---

## PR-B — Merge instead of orphan

### Task 1: Surface the cleanup outcome and retry a partial merge inline

**Files:**
- Modify: `lib/core/services/firebase_functions_service.dart:18-26` (return `CleanupOutcome`)
- Modify: `lib/features/auth/services/auth_recovery_service.dart` (typedef `23-27`, default closure `56-62`, cleanup block `321-346`, stale "~70s" comment `:326` → 60s)
- Test: `test/unit/firebase_functions_service_cleanup_outcome_test.dart` (new) + `test/unit/auth_recovery_service_test.dart` (extend; also the typed `buildService` seam param `:70-74` + default closure `:87-89` must return `CleanupOutcome`)
- Modify (round-2 [P2] — typedef ripple, or the tree won't compile): `test/unit/auth_recovery_service_restart_guarantee_test.dart:67` and `test/unit/auth_recovery_service_inflight_op_test.dart:64` — their inline `async {}` cleanup closures become `async => const CleanupOutcome(cascadeFailed: [])`.

> **Land Task 1 atomically** (wrapper + typedef + closure + `completeRecovery` consumption + ALL FOUR test files above) so the tree compiles between commits (P2-2).

**Step 1 — Failing test (wrapper).** Fake `FirebaseFunctions` whose `httpsCallable('cleanupAnonUidArtifacts').call(...)` returns `.data = {'cascadeFailed': <list>, ...}`. Assert `cascadeFailed:[] → complete==true`; `cascadeFailed:['g1'] → complete==false, cascadeFailed==['g1']`.

**Step 2 — Run, expect FAIL** (`CleanupOutcome` undefined).

**Step 3 — Implement** the `CleanupOutcome` class + parse in the wrapper (tolerate missing/non-list `cascadeFailed` as `[]`):
```dart
class CleanupOutcome {
  const CleanupOutcome({required this.cascadeFailed});
  final List<String> cascadeFailed;
  bool get complete => cascadeFailed.isEmpty;
}
```
```dart
Future<CleanupOutcome> cleanupAnonUidArtifacts({required String oldUid, required String cleanupSecret}) async {
  final result = await _functions.httpsCallable('cleanupAnonUidArtifacts')
      .call({'oldUid': oldUid, 'cleanupSecret': cleanupSecret});
  final raw = (result.data is Map) ? (result.data as Map)['cascadeFailed'] : null;
  return CleanupOutcome(
    cascadeFailed: (raw is List) ? raw.whereType<String>().toList(growable: false) : const [],
  );
}
```

**Step 4 — Failing test (completeRecovery inline retry).** In `auth_recovery_service_test.dart`, with current anon `OLD`, `signInWithEmailLink → NEW`:
- cleanup returns `complete` first try → callable invoked **once**, no Sentry error, sequence ends `…signInWithEmailLink, cleanup:OLD, restart`.
- cleanup returns `cascadeFailed:['g1']` then `complete` on 2nd call → callable invoked **twice** (inline retry), no Sentry error.
- cleanup returns `cascadeFailed:['g1']` both times → callable invoked **twice**, then a `recoveryCleanupFailureRecorder` call with `cascadeFailed` data; recovery still **returns the credential** + restarts (finally).
- cleanup **throws** then succeeds → invoked twice, no recorder; throws both (non-permission-denied) → recorder called, recovery still **returns the credential** + restarts.
- **(round 2, worked example 3)** cleanup **throws**, then retry throws `FirebaseFunctionsException(code: 'permission-denied')` → invoked twice, **NO recorder** (success-equivalent: intent consumed by a completed first invocation), recovery returns + restarts.
- **(round 2)** update the two pre-existing always-throw tests (`:410` 'recovery succeeds when cleanup callable throws', `:475` PII-exclusion) — under retry semantics their closure is now invoked **twice**; pin the new invocation count and the new recorder message.

**Step 5 — Implement.** Change the typedef + default closure to return `CleanupOutcome`. In `completeRecovery`'s `if (oldUid != null && cleanupSecret != null && result.user?.uid != oldUid)` block, replace the single awaited call with: call once; if it threw or `!outcome.complete`, retry **once** (idempotent — `cleanupAnonUidArtifacts.ts` is convergent-on-retry per #275, and on a structured partial failure the server kept the intent). **Both the call and the retry stay inside try/catch — a thrown retry is recorded-and-swallowed, never rethrown (round 2: preserves the existing `return result` contract; the bootstrap must still receive the credential).** Failure disposition: if the first attempt **threw** and the retry throws `permission-denied` → breadcrumb only (worked example 3); any other still-failing terminal state → `_recoveryCleanupFailureRecorder(message: 'Recovery cleanup incomplete', data: {'groupsFailed': outcome.cascadeFailed})`. No prefs marker, no boot hook. Keep the existing `finally` (op-state clear + restart) unchanged. Fix the `:326` "~70s" comment to 60s while here.

**Step 6 — Run, expect PASS.** **Commit** `feat(recovery): surface cleanup outcome + inline-retry a partial merge`.

---

### Task 2: Merge-consent dialog replaces the sign-out-first dialog

**Files:**
- Create: `lib/features/auth/widgets/merge_on_recover_dialog.dart`; Delete: `lib/features/auth/widgets/sign_out_first_dialog.dart`
- Modify: `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb` (new keys; remove `authSignOutFirst*` after Task 4)
- Test: `test/features/auth/confirm_dialogs_test.dart` (replace the `SignOutFirstDialog` group)

**Steps:** RED (`MergeOnRecoverDialog.show` → true on confirm / false on cancel / null on barrier dismiss; renders new strings) → implement (mirror old dialog structure). Note (round 2): `confirm_dialogs_test.dart` generates its groups from a record **list** (`:70-75`) — "replace the SignOutFirstDialog group" means swapping that list entry for a `MergeOnRecoverDialog` entry, not editing a literal `group()` block. Keys:
- `authMergeOnRecoverTitle`: "Restore your account"
- `authMergeOnRecoverBody`: "We'll sign you in to that account and move this phone's trips and expenses into it. Nothing on this device is lost."
- `authMergeOnRecoverConfirm`: "Restore and merge"; Cancel: reuse `commonCancel`.
- Add Arabic equivalents in `app_ar.arb`.
→ GREEN → **Commit** `feat(recovery): merge-consent dialog`.

---

### Task 3: RecoverScreen populated path merges (no sign-out)

**Files:**
- Modify: `lib/features/auth/screens/recover_screen.dart:47-67` (`_confirmIfDevicePopulated`) + doc `19-27`
- Test: `test/features/auth/recover_screen_test.dart` (rewrite populated-device tests — these invert current pins)

**Step 1 — Failing tests (RED):** (round 2 — the existing populated-device pins don't all "invert": the marks-dirty-before-signOut test at `recover_screen_test.dart:190-224` loses its entire premise once the screen-level `signOut` is gone — **DELETE it**, don't mechanically invert; the cancel test at `:162-188` is re-keyed from `signOutFirst.*` to the new `MergeOnRecover` keys; the fresh-device happy path `:140-160` and the FR-REC-5/`:226` tests stay as-is.)
- `on a populated device, recovery proceeds WITHOUT signing out`: seed `userGroupsProvider` ≥1 group, confirm merge dialog → `verifyNever(() => firebaseAuth.signOut())`, `verify(sendRecoveryLink).called(1)`, routes to `/recover/pending`.
- `on a populated device, cancelling the merge dialog blocks the send`: cancel → `verifyNever(sendRecoveryLink)`.
- `populated device does NOT mark persistence dirty on the recover screen`: `kFirestorePersistenceDirtyKey` NOT set by the screen (merge keeps this UID's data; `completeRecovery:309` still marks dirty before its own restart).

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement:**
```dart
Future<bool> _confirmIfDevicePopulated() async {
  final groups = ref.read(userGroupsProvider).valueOrNull ?? const [];
  if (groups.isEmpty) return true;
  final confirmed = await MergeOnRecoverDialog.show(context);
  return confirmed == true;
}
```
Remove the `markFirestorePersistenceDirty` + `signOut()` block. Update the class doc: populated-device recovery now MERGES (no sign-out, no orphan); cite this plan + the FR-REC-2/3/4 re-scope.

**Step 4 — GREEN.** Run `flutter test test/features/auth/ test/unit/auth_recovery_service_test.dart test/unit/auth_email_link_bootstrap_test.dart`. **Commit** `fix(recovery): populated-device restore merges instead of orphaning (#427)`.

---

### Task 4: Remove dead pins; update docs

**Files:**
- Modify/Delete obsolete `SignOutFirstDialog` assertions (`test/features/auth/confirm_dialogs_test.dart`); verify `grep -rn SignOutFirstDialog lib test` is empty.
- Modify: `docs/ACCOUNT-RECOVERY.md` — round 2 found THREE stale spots, not one: (a) §10:384 `→ FirebaseAuth.signOut() -- discards tempUid session` (false since #414); (b) §10:387 `→ unawaited(cleanupAnonUidArtifacts(…))` — false, the cleanup is **awaited** at `auth_recovery_service.dart:331`; (c) §7:266-267 "The callable is **fire-and-forget** from the client… the cleanup runs in the background" — same falsehood. Sweep all three; rewrite the populated-device section (swap-and-orphan → consented merge).
- FR-REC-2/3/4 re-scope (round 2): their definitions live ONLY in a **deleted** design doc (`docs/design/account-recovery.md` §5.2, removed in `5f1d1e64`) — `docs/ACCOUNT-RECOVERY.md` never defined them. Quote the superseded text inline when re-scoping (FR-REC-2 "recovery refused unless sign-out-first confirmed" → consented merge; FR-REC-3 "prior anon UID signed out and discarded" → migrated, never discarded; FR-REC-4 "no migration step required" → migration IS the mechanism), and update the live code-comment cites: `recover_screen.dart:19-27` doc comment (Task 3 already rewrites it) — `sign_out_first_dialog.dart:7` dies with Task 2; the FR-REC-5 test ref is unaffected.
- Remove `authSignOutFirst*` (3 keys: Title/Body/Confirm — `app_en.arb:1729-1737`, `app_ar.arb:767-769`) from both ARBs **and** from `test/unit/generated_l10n_surface_test.dart` (`:70-71` AR≠EN assertion + `:370-372` surface list — round 2: the grep never comes up empty without this), then regenerate l10n.

`flutter analyze` clean; `flutter test` green. **Commit** `docs(recovery): merge-on-restore supersedes sign-out-first; drop dead dialog`.

---

### Task 5: Regression — a restored email-linked session is KEPT on cold boot (P2-1)

**Files:**
- Test: extend `test/integration/firebase_auth_test.dart` (round-2 cite fix: the #213 session tests live THERE, `:103-227` — `test/unit/firebase_config_session_test.dart` does not exist; current coverage seeds `isAnonymous: true` only, so the email-linked case is genuinely new coverage)
- (No source change expected — this PINS the merge precondition: `ensureAnonymousSession`'s restored branch is uid-type-agnostic, `firebase_config.dart:94-95` checks only `restoredUser != null`.)

**Step 1 — Test.** With `firebase_auth_mocks`, seed a persisted **non-anonymous** user (email set) as the restored session; run `ensureAnonymousSession(runCacheBarrier: false)`; assert `currentUser` is the SAME email-linked uid and `signInAnonymously` was **never** called. (Mirrors the #213 anon-kept test but for an email session — this is what guarantees a post-merge restart lands on `NEW`, not a fresh anon.)

**Step 2 — Run.** If GREEN → the invariant already holds (likely, given #213/#105). If RED → STOP: this is a merge blocker, escalate before continuing.

**Commit** `test(recovery): restored email session is kept on cold boot`.

> **Device-QA gate (P2-1), before PR-A:** on an Android build, complete a real recovery on a populated device, force the restart, cold-boot, and confirm Profile shows the linked email + the merged groups. Record in REAL-DEVICE-QA. Do not ship PR-A (reachable Restore) until this passes.

---

## PR-A — Reachable Restore (after PR-B + the P2-1 device-QA gate)

### Task 6: RecoverScreen accepts an optional prefilled email
**Files:** `lib/features/auth/screens/recover_screen.dart` + `lib/core/router/app_router.dart:445-451` (the `/recover` route); Test: `recover_screen_test.dart`.
Round 2: follow the codebase's existing pattern — the sibling `/recover/pending` route already extracts via `_emailFromRouteState(state)` (`app_router.dart:75-77`, `state.uri.queryParameters['email'] ?? ''`) in the route builder and passes a constructor param. Do the same: `RecoverScreen(initialEmail: …)` from the pageBuilder (today it's `const RecoverScreen()` with no params), seed `_emailController` in `initState`.
RED (mount `/recover?email=x@y.com` → field prefilled) → implement → GREEN → **Commit** `feat(recovery): RecoverScreen prefills email from query param`. (Query-param, not `extra` — cold-deep-link safe.)

### Task 7: "Restore that account instead" CTA on the already-linked error
**Files:** `lib/features/auth/screens/link_email_screen.dart` (store the failing `code` — round 2 confirmed: today only the humanized `String? _serverError` survives the catch (`:34`, catch at `:67-69`), so add a code/flag field set at the catch site; `_humanizeError:83-86` already groups exactly these three codes; when in `{credential-already-in-use, email-already-in-use, provider-already-linked}` render `Key('linkEmail.restoreInstead')` → `context.push('/recover?email=<entered>')`); `app_en.arb`+`app_ar.arb` (`authRestoreInstead`: "Restore that account instead"); Test: `link_email_screen_test.dart`.
**RED:** the CTA appears on the conflict, tapping it navigates to `/recover?email=…` and **does NOT** call `completeRecovery`/`signInWithEmailLink` (preserves the #414 no-auto-recover invariant — verified untouched in `auth_email_link_bootstrap_test.dart`). → implement (CTA only navigates) → GREEN → **Commit** `feat(recovery): offer Restore from the already-linked error (#428)`.

### Task 8: Profile "Restore a different account" row (when unlinked)
**Files:** `lib/features/settings/screens/profile_screen.dart` (`_AccountCard:816`, add a `_PrefRow` (`:1074`) → `/recover`, shown when `linkedEmailProvider == null` (`auth_provider.dart:44-49`), placed under the linked-email row `:884-917` in the `_RowsCard(rows: […])` list `:882-946`); `lib/features/settings/keys/profile_keys.dart` (`restoreAccountTile`); `app_en.arb`+`app_ar.arb` (`profileAccountRestore`: "Restore a different account"); Test: `profile_screen_test.dart`.
RED (row visible + routes to `/recover` when unlinked; absent when linked) → implement → `flutter analyze` → **Commit** `feat(recovery): reachable Restore entry in Profile (#428)`.

---

## Gate & ship checklist

- [x] **Re-run the Gate** — DONE 2026-06-10: round 2 ran as 2 fresh-context Opus reviewers + 4 claim-verifiers; **both verdicts PASS, 0 P1**; the 1 P2 + 5 P3 + claim corrections are folded into this revision (see "Gate round 2" above). No further round owed unless the plan's scope changes.
- [ ] PR-B lands before PR-A; PR-A gated on the P2-1 device-QA pass.
- [ ] Money/identity paths have RED-first tests (Tasks 1, 3, 5 load-bearing); the `cascadeFailed` worked example is covered in Task 1's tests; the lost-response/permission-denied case (worked example 3) has its own Step-4 test.
- [ ] `flutter analyze` clean; `flutter test` green; `git diff` touches **no** `functions/**` and **no** `security/firestore.rules` (reuses deployed machinery); `tool/pending_deploy.sh` shows nothing new.
- [ ] PR bodies: `Closes #427` (PR-B) / `Closes #428` (PR-A); `Spec: docs/plans/2026-06-10-recovery-merge-reachable-restore.md`.
- [ ] `/automerge` classifies these Gate-category (auth screens + service) → merge-time fresh-Opus review + refuter must clear.
- [ ] If the "Linked email: not set" report (#429) reproduces after PR-B ships, escalate it out of the deferred bucket.
