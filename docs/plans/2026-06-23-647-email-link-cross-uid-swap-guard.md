# Plan: #647 — Email-link cross-UID swap guard (P1 data-loss hole only)

**Date:** 2026-06-23
**Issue:** #647 (P1, data-integrity, privacy) — blocks #648 (join un-gate)
**Gate:** REQUIRED (recovery cascade / cross-UID swap / deep-link auth). Run `/run-the-gate` on this spec before code.

## Problem (verified open at `auth_email_link_bootstrap_provider.dart:138-140`)

The email **RECOVER** deep link (`op=recover`) dispatches straight into
`service.restoreWithEmailLink(link)` with **no emptiness gate**. `restoreWithEmailLink`
(`auth_recovery_service.dart:333-398`) is a cross-UID discard-shell swap that
`engageIsolation()` → flush → `signInWithEmailLink` → **guaranteed `restart()` in its
`finally`**. Once entered it cannot be aborted. So if the outgoing anon shell holds
ledger memberships, the swap silently orphans them: `waitForPendingWrites` already
flushed them to the server under the *old* anon UID A; after the A→B swap the user is B
with none of A's trips, and A persists as an orphaned-but-active member. This is
identity/continuity loss for that person (#414 / #216 lineage).

Today the anon shell is empty by construction (anon can't create/join behind the #441 PR2
gate), so the hole is **latent**. #648 (join un-gate) populates the shell and makes it
**live** — hence #647 must land first/with it.

The same membership predicate already guards the **other two** cross-UID entrances:
- `profile_screen.dart:1099-1100` — `showRestore` gated on `userGroupsProvider…isEmpty` (loading/error → hidden).
- `durable_credential_sheet.dart:171-180` — conflict switch offered only on `groups.isEmpty` (loading → progress; error → dead-end).

The deep-link recover path is the **one entrance that never consults it**.

## Scope of THIS PR — P1 guard only

IN (closes the data-loss hole):
- **(a)** Wire the membership predicate into the bootstrap recover branch, **before** `restoreWithEmailLink`.
- **(c)** Fail-safe + defer-then-decide semantics: proceed **only** on `AsyncData && isEmpty` (or no current user); loading defers to first emission; hang→timeout and error→`false` (block). Never `loading/error → proceed`. On block, **clear** `inFlightOp` + `pendingLinkEmail` (no phantom recover op — Gate R2 P1); the live anon session is never signed out.
- **(b)** Guard-rail the adjacent email link-conflict cell: source comment at `completeEmailLink` + a #647-labelled regression test pinning *conflict → no UID swap* (safe-by-absence → safe-by-assertion).

DEFERRED to land with #648 (`Refs #647`, boxes named — NOT `Closes`):
- **(d)** Reword the *other two* entrances' copy (profile hides; sheet terse) silent→explicit. They already correctly **block**; copy is cosmetic, not a data-loss fix. The bootstrap block gets honest copy here (inherent to (a)).
- **(e)** Nudge-fork re-verification. The current #285 nudge (`account_backup_nudge.dart:115`) already routes through the `groups.isEmpty`-gated `showDurableCredentialSheet` — **already compliant**. Re-assert when #648 adds a new nudge.

OUT (non-goals): no merge engine (deleted #441 PR5 — `restoreWithEmailLink` comment `:322-326`); no `firestore.rules` / Cloud Functions / schema / `SplitMode` change; no `restoreWithEmailLink` body change (the gate is the caller's).

## The change (3 edits, ~35 LOC + tests)

### 1. `auth_email_link_bootstrap_provider.dart`

> **[Gate R1 P1 #1 — cold-start race]** `userGroupsProvider` keys on
> `firebaseUserProvider.valueOrNull?.uid` (`group_provider.dart:612-618`). On the
> cold-start `getInitialLink()` recover path (app *launched by* the email link — the
> canonical fresh-device case) `firebaseUserProvider` (a fresh `authStateChanges()`
> subscription whose current-user replay is a **microtask**) can still be `AsyncLoading`
> at the instant the gate first reads it → `uid == null` → `userGroupsProvider` returns
> `Stream.value([])` → `.future` resolves **immediately to `[]`** → the gate sees a FALSE
> empty and PROCEEDS on a populated shell. A bare `timeout` guards a hang, not a
> fast-stale empty. **Fix: resolve the auth UID FIRST** (`await
> firebaseUserProvider.future`), so the membership read targets the settled outgoing
> anon UID, never a still-loading `null`.

- New provider (testability seam, mirrors the service's injectable `pendingWritesTimeout`):
  ```dart
  final recoverSwapGateTimeoutProvider =
      Provider<Duration>((_) => const Duration(seconds: 5));
  ```
- New top-level helper. A SINGLE `.timeout(timeout)` bounds the whole gate (P2: total
  user-visible defer ≤ one timeout, not 2×):
  ```dart
  Future<bool> _outgoingShellProvablyEmpty(Ref ref, Duration timeout) async {
    try {
      return await _resolveShellEmpty(ref).timeout(timeout);
    } catch (_) {                     // hang→timeout OR stream error → block
      // (log: could not confirm empty → fail-safe block)
      return false;
    }
  }

  Future<bool> _resolveShellEmpty(Ref ref) async {
    // Settle the UID before the membership read (Gate R1 P1 #1).
    final user = await ref.read(firebaseUserProvider.future);
    if (user == null) return true;    // no shell → nothing to orphan → proceed
    final groups = await ref.read(userGroupsProvider.future);
    return groups.isEmpty;
  }
  ```
- Recover branch (`:139`), before the call:
  ```dart
  if (op == AuthRecoveryService.opRecover) {
    final timeout = ref.read(recoverSwapGateTimeoutProvider);
    if (!await _outgoingShellProvablyEmpty(ref, timeout)) {
      // [Gate R2 P1] CLEAR the recovery handshake on block. A blocked recover
      // performed NO swap and NO restart, so the persisted inFlightOp='recover'
      // is a PHANTOM: GateIntentReplay (gate_intent_replay.dart:17-18) skips
      // create/join gate-intent replay on EVERY boot while a recover op is
      // pending — a phantom op silently drops a legitimate replayed form. Clear
      // both keys (guarded; a failed prefs write must not crash the listener).
      try {
        await service.clearInFlightOp();
        await service.clearPendingEmail();
      } catch (error, stack) {
        FirebaseConfig.log('Recovery: clear op-state after block failed',
            error: error, stackTrace: stack);
      }
      // breadcrumb + honest snackbar (isError: true, 8s); leave the live anon
      // SESSION intact (never signOut, #213/#414); return — no swap.
      return;
    }
    final result = await service.restoreWithEmailLink(link);  // unchanged
    …
  }
  ```
  The next legitimate recover re-arms the handshake via `sendRecoveryLink` (`auth_recovery_service.dart:162-169`, re-sets both keys), so clearing on block does not strand a real retry. On the PROCEED path the op-state is untouched — `restoreWithEmailLink`'s `finally` clears it (`:395`).
- `_showSnack` gains an optional `Duration duration = const Duration(seconds: 4)`; the block snackbar passes `8s` (matches the CLAUDE.md blocked-leave/remove convention).
- New imports: `firebaseUserProvider`, `userGroupsProvider` from `groups/providers/group_provider.dart`.
- Honest block copy (money app; must NOT imply settling preserves history), passed `isError: true` (red bg) + `duration: 8s`:
  > *Recovery would switch to your saved account and leave this device's current trips behind — they're tied to a temporary identity that can't be moved. Resolve them first.*
  Hardcoded English, matching this file's existing un-localized recovery snackbars (the provider has no `BuildContext`/`l10n`).
- Riverpod note (Gate R2 P3): lockfile resolves `flutter_riverpod 2.6.1` (constraint `^2.4.9`); `.future` first-emission + dependent-rebuild semantics the gate relies on are identical in both — reason against 2.6.1.

### 2. `auth_recovery_service.dart` — (b) safe-by-assertion comment in `completeEmailLink` body
**[Gate R1 P3]** Place the comment inside the `completeEmailLink` doc/body (function header at `:178`), NOT on the `linkWithCredential` call line (`:197`). States: completeEmailLink is SAME-UID and has no conflict→switch route; a future "make email symmetric with Google" PR that offers switch-on-conflict MUST route through the same `userGroupsProvider.isEmpty` gate, never an unguarded `restoreWithEmailLink`.

### 3. Tests — `test/unit/auth_email_link_bootstrap_test.dart`

> **[Gate R1 P1 #2 — don't mask the race]** Overriding `userGroupsProvider` directly with
> a pre-settled stream bypasses the `firebaseUserProvider`→loading→`Stream.value([])`
> race that the P1 turns on — the suite would go green while the hole ships. So the gate
> tests drive the **REAL** `userGroupsProvider` through two override seams instead:
> - `firebaseUserProvider.overrideWith((ref) => <controllable User? stream>)` — lets a
>   test hold the UID in `loading`, then settle it AFTER the deep link arrives.
> - `groupServiceProvider.overrideWithValue(_MockGroupService())` with
>   `when(() => gs.watchUserGroups(any())).thenAnswer((_) => <groups stream>)` — supplies
>   the membership result without Firestore (the real `userGroupsProvider` body runs:
>   reads `firebaseUserProvider` uid, calls `watchUserGroups(uid)`).

New mocks/fixtures: `_MockGroupService extends Mock implements GroupService`, `_MockUser extends Mock implements User` (`when(uid)→'anonA'`, `when(isAnonymous)→true`), `_group()` factory (copy from `durable_credential_sheet_conflict_test.dart:34`). New imports: `group_provider.dart`, `group_model.dart`, `firebase_auth` `User`.

**[Gate R3 P2 — update ALL opRecover-routing tests]** EVERY existing test that sets `op=opRecover` reaches the gate after the change and will hit the REAL `firebaseUserProvider` (`group_provider.dart:603`, NO try/catch) → `[core/no-app]` unless given the defaults. That is **7** tests: `:76` (base route), `:141` (cold-start initial-link), `:160` (custom-scheme), `:179` (FirebaseAuthException-doesn't-crash — **easy to miss**), `:304` (recover-failure-no-refallback), `:327` + `:353` (dedupe ×2). All get the settled-user + empty-groups defaults (`firebaseUserProvider → Stream.value(anonUser)`, `watchUserGroups → Stream.value([])`) so they still proceed → restore. This models "settled empty shell → proceed" through the real chain, NOT by masking `userGroupsProvider`. (The `opLink`/missing-email/conflict tests never enter the recover branch — unaffected.)

**[Gate R2 P2 — settle discipline]** The gate now chains `firebaseUserProvider.future` → `userGroupsProvider` rebuild → `watchUserGroups` first-emit. A lone `pumpEventQueue()` can under-drain that multi-provider chain. After `userController.add(anonUser)`, drain generously — a `settle()` helper looping `await pumpEventQueue()` several times (precedent: `home_balance_once_104_test.dart` drains 12× `Future.delayed(Duration.zero)`). The gate `await` is inline before `restoreWithEmailLink` (do NOT `unawaited` it — that breaks both the RED and the block).

## Verification principles (run now, reported out loud)

1. **Callsite classification.** Only OUTBOUND mutation on this path = `restoreWithEmailLink` (UID swap). The gate is INBOUND (reads `userGroupsProvider`, display/read-only — never feeds a write). `completeEmailLink` is SAME-UID, not a cross-UID swap. ✅
2. **Concrete claims vs code.** `restoreWithEmailLink` restart-in-finally `:388-397`; merge engine deleted comment `:322-326`; `userGroupsProvider` `group_provider.dart:612-618` → `watchUserGroups` `:523` → `.where('memberIds', arrayContains: uid)` `:526`; guards `profile_screen.dart:1099`, `durable_credential_sheet.dart:175`; nudge `account_backup_nudge.dart:115`; boot order `main.dart:140,176,222` (bootstrap consumed post-anon-session). All re-grepped this session. ✅ **NOTE (Gate R1):** post-anon-session settles `FirebaseConfig.currentUser`, but the Riverpod `firebaseUserProvider` (`group_provider.dart:603`) re-subscribes to `authStateChanges()` and replays via a microtask — so it can read `AsyncLoading` at the gate's first synchronous read. The gate awaits `firebaseUserProvider.future` to collapse that lag before the membership read.
3. **One read-path per write-path.** Write = the UID swap. Reader after it = the cold-boot restart re-renders all UI under UID B. The guard's job is to *prevent the write* when the outgoing UID A still has memberships; the reader of the gate's bool is the recover branch itself. **Second consumer of the persisted `inFlightOp` (Gate R2):** `GateIntentReplay.maybeReplay` (`gate_intent_replay.dart:17-18`) reads `inFlightOpPrefsKey` and *skips* create/join replay while `=='recover'`. So the block path must clear `inFlightOp`, else a phantom recover op suppresses a legitimate gate-intent replay on every boot. ✅
4. **Fields from type.** No schema/field change. `userGroupsProvider` is `StreamProvider<List<Group>>`; gate consumes only `List.isEmpty`. ✅
5. **Data contract.** `_outgoingShellProvablyEmpty(Ref, Duration) → Future<bool>`; `true ⇒ proceed (restore)`, `false ⇒ block`. `recoverSwapGateTimeoutProvider: Provider<Duration>`. ✅
6. **Arithmetic decomposition.** No money math here, but the *WHY*: the orphaned data is the anon UID's `netBalance`/ledger — irरecoverable post-swap because the merge engine was deleted (#441 PR5). The gate is the only defense. ✅
7. **Adversarial pass — orthogonal axis.** Fix axis = identity/continuity. Tests exercise the **async-state axis** (loading-defer→proceed, hang→timeout→block, stream-error→block) AND the **membership axis** (empty→proceed, non-empty→block) — not just the happy path. ✅

## Tests (RED first, then GREEN)

New (guard) — all drive the real `userGroupsProvider` via `firebaseUserProvider` + `groupServiceProvider`:
- **HEADLINE — `opRecover cold-start race: UID settles AFTER dispatch, shell populated → NO swap`**. `firebaseUserProvider` = controllable broadcast `Stream<User?>` with no emission yet; `watchUserGroups('anonA') → Stream.value([_group()])`. Sequence: attach → `uriStream.add(link)` → `pumpEventQueue` (gate now awaits `firebaseUserProvider.future`) → `userController.add(anonUser)` → `pumpEventQueue` → `verifyNever(restoreWithEmailLink)`. **RED before fix** (gate reads `userGroupsProvider.future` while UID loading → `null` → `[]` → proceeds → restore called); **GREEN after** (awaits UID → groups `[grp]` → blocks). This is the exact P1 #1 reproduction.
- `opRecover + settled populated shell → blocks` — `firebaseUserProvider → Stream.value(anonUser)`, `watchUserGroups → Stream.value([_group()])`; `verifyNever(restoreWithEmailLink)`.
- `opRecover + settled empty shell → proceeds` — `Stream.value(anonUser)` + `watchUserGroups → Stream.value([])`; `restoreWithEmailLink` called once.
- `opRecover + groups stream error → blocks (fail-safe)` — `watchUserGroups → Stream.error(...)`; `verifyNever`.
- `opRecover + gate hang → blocks (fail-safe)` — `firebaseUserProvider` never emits + `recoverSwapGateTimeoutProvider` override (e.g. 50ms); `verifyNever` after waiting past the timeout.
- `opRecover + no current user → proceeds (nothing to orphan)` — `firebaseUserProvider → Stream.value(null)`; `restoreWithEmailLink` called once (covers the `user == null → true` branch).
- **`opRecover blocked → clears inFlightOp + pendingEmail (no phantom recover op)`** [Gate R2 P1] — settled user + populated shell; assert `verify(() => service.clearInFlightOp()).called(1)` and `verify(() => service.clearPendingEmail()).called(1)`, plus `verifyNever(restoreWithEmailLink)`. (`service` is mocked; stub both clears `thenAnswer((_) async {})` in `setUp`.)

New (b guard-rail):
- `#647: opLink conflict (email-already-in-use) never swaps UID` — `completeEmailLink` throws; `verifyNever(restoreWithEmailLink)` (security property; the existing #414 group covers the family — this names the #647 invariant).

Updated: existing `opRecover`/cold-start/custom-scheme/recover-failure/dedupe tests get the settled-user + empty-groups defaults (proceed path preserved through the real chain).

## Commands
```
flutter test test/unit/auth_email_link_bootstrap_test.dart   # RED → GREEN
flutter test test/features/auth/ test/unit/                  # no regressions
flutter analyze
```

## Merge
`Refs #647` in **commit body + PR body** (partial: (d)/(e) deferred — squash auto-closes from the commit message, so `Refs` must be there). Name the unmet boxes in the PR. Issue stays open re-scoped.
