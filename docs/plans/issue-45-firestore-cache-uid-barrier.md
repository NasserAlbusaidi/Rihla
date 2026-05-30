# Issue #45 — Seal the cross-UID Firestore SDK cache leak (boot barrier + isolation overlay + restart-on-swap)

**Scope:** ONE PR, complete P0 fix. A **cold-start cache barrier** is the single site that calls `clearPersistence()` (only legal on an un-started instance). Every **in-session UID swap** (email-link recovery, sign-out, account deletion): engages a **full-screen cache-isolation overlay** (covers all cached UI before any auth change) → flushes pending writes → sets a durable dirty flag → performs the auth change (recovery additionally **awaits its server cleanup to completion** under the overlay) → triggers a **true app restart**; the restart produces a cold boot where the barrier clears. The overlay — not restart timing — is what guarantees no cached financials render during the swap.
**Base:** `main` (`c25388d`, post-#65). Firestore SDK cache is the only on-device cache; nothing clears it (`grep -rn 'clearPersistence|\.terminate(' lib/ test/` → 0). Android-only launch (iOS soft-deferred) makes a real process restart viable.
**Status:** R1 = 2 P1 + 3 P2 → "full fix, restart-based". R2 = 3 P1. R3 = 1 P1 + 4 P2. R4 = **1 P1** (P1-2: the ~60s cap still could restart before a valid 60–540s scrub finished) + P2-1 (bootstrap chain not torn down on isolation). **v3.2 (this rev):** drop the custom cap entirely — await the callable's natural terminal state (default ~70s client timeout bounds it); the server scrub completes independently of client disconnect, so this is byte-for-byte main's scrub outcome (§3.6). Plus `engageIsolation` invalidates the leaf subscription providers (P2-1). **Gate R5 = no P1 blockers — APPROVED for implementation.** (R5 confirmed P1-2 closed: `cleanupAnonUidArtifacts` is a gen2 `onCall` that completes server-side regardless of client disconnect; remaining R5 P2-1 = invalidate `authEmailLinkBootstrapProvider`+`notificationServiceProvider` directly, folded in above.) P1-1/P1-3 closed R3; all P2/P3 are impl-detail or device-check (§6).
**Threat model (carried #50 Gate P2):** `clearPersistence()` is not a secure on-disk overwrite (`cloud_firestore-6.2.0/.../firestore.dart:95-104`). Scope = user-visible stale reads across a UID swap. Server rules deny cross-UID server reads (`firestore.rules:238/379/565-566/663/735`), bounding the leak to the offline/cached window.

---

## Part 1 — The leak (confirmed; 4-reader audit + codex R1/R2 re-verify)
Persistence on, unbounded (`firebase_config.dart:51-54`); nothing clears it on any swap. Fixed-path (non-uid) reads replay UID X's docs to UID Y:

| Read | Path (no uid) | Class | Evidence |
|---|---|---|---|
| Event expenses / settlements | `groups/{gid}/events/{eid}/{expenses,settlements}` | BOTH | `expense_provider.dart:51-64` |
| Group settlements / balances | `groups/{gid}/settlements` | BOTH | `group_balance_provider.dart:40-44,112-164` |
| Events list / detail | `groups/{gid}/events`, `.../{eid}` | BOTH | `event_provider.dart:36-74` |
| Group / members detail | `groups/{gid}`, `groups/{gid}/members` | BOTH | `group_provider.dart:408-437` |
| Activity feeds | `groups/{gid}/activity`, `.../activity_logs` | INBOUND | `group_activity_service.dart:39-55` |

`userGroupsProvider` (uid-scoped, `group_provider.dart:392-402`) yields the `gid`s. **Memory correction (code wins):** "barrier complete" obs are false; commit `99001eb` is a non-ancestor SQLite-only branch; no `safeUidProvider` exists; **no `AccountJobCoordinator` exists in `lib/`** (R2 grep) — stale memory.

---

## Part 2 — UID-swap paths and handling
| # | Path | Code | Handling |
|---|---|---|---|
| 1 | Recovery (anon X → linked Y) | `auth_recovery_service.dart:226-296`; in-process via `auth_email_link_bootstrap_provider.dart:151-153` | overlay → flush → dirty → signOut → signInWithEmailLink → **await cleanup to completion (bounded)** → restart |
| 2 | `completeEmailLink` (link, same UID) | `:194-218` | not a swap — no change |
| 3 | `signOutCurrentDevice` (Y → anon Z) | `:303-324` | overlay → flush → dirty → signOut → restart (**drop** in-session anon mint; restart re-mints) |
| 4 | Deletion (Y → anon Z next boot) | `data_deletion_service.dart:32-51` | overlay → **await cascade (existing :39)** → dirty → signOut → restart |
| 5 | internal-error restored-session retry | `firebase_config.dart:109-126` | cold-start → barrier **force-clears** via swap-bool (P1-3) |
| 6 | reinstall / OS restore | cfg `:51-54` | cold-start, prefs-dependent (§3.2) |

---

## Part 3 — Design

### 3.1 Markers (new SharedPreferences keys)
- `auth.lastActiveUid` (String) — uid the cache belongs to; written at end of every successful boot reconcile.
- `auth.firestorePersistenceDirty` (bool) — set `true` by an in-session swap **before** the auth change; cleared by the barrier after a successful clear. Crash-safety net.

### 3.2 Decision rule (pure, table-tested) — adds `forceClear` (P1-3 fix)
```
bool shouldClear({String? lastActiveUid, required String currentUid, required bool dirty, required bool forceClear})
    => forceClear || dirty || (lastActiveUid != null && lastActiveUid != currentUid);
```
- `forceClear` = "a UID swap demonstrably happened on THIS boot" (from `recoverRestoredSessionIfNeeded`). Closes P1-3: upgrade-first-boot where restored X fails token verify → fresh Y, `lastActiveUid==null`, `dirty==false`, but `forceClear==true` → clear.
- `lastActiveUid == null` + no force + no dirty → **no clear, adopt** (P2-3: don't drop every upgrader's same-UID unsynced writes).
- Drift / dirty / forceClear → clear.
- Residual (documented, deferred to device-QA): reinstall where cache survives but prefs are lost AND no in-boot swap occurred → null marker, no clear. Rare, OS-specific.

### 3.3 Seams (injectable; FakeFirebaseFirestore models neither real persistence nor terminate — §6)
```
abstract class FirestoreCacheGate { Future<void> clearPersistence(); }
class FirebaseFirestoreCacheGate implements FirestoreCacheGate {...}

abstract class CacheIsolationController {                 // covers the in-session window
  void engageIsolation();                                 // flip the overlay flag — synchronous, before any auth change
  Future<void> restart();                                 // TRUE process restart (NOT a flutter_phoenix rebirth)
}
class PlatformCacheIsolationController implements CacheIsolationController {...}  // overlay flag + restart_app/MethodChannel (Intent+Runtime.exit on Android)
// WIRING (R3 P2-2): services have no `ref`. The controller is built in the provider layer with a notifier/container handle:
//   cacheIsolationProvider = StateProvider<bool>((_) => false);
//   PlatformCacheIsolationController({required Ref ref}) ... engageIsolation() => ref.read(cacheIsolationProvider.notifier).state = true;
//   authRecoveryServiceProvider / dataDeletionServiceProvider inject ref.read(cacheIsolationControllerProvider). Tests inject a fake recording engage()/restart().

class CacheUidBarrier {
  CacheUidBarrier({required SharedPreferences prefs, required FirestoreCacheGate cacheGate});
  Future<void> reconcile(String currentUid, {bool forceClear = false}) async {
    final last  = prefs.getString('auth.lastActiveUid');
    final dirty = prefs.getBool('auth.firestorePersistenceDirty') ?? false;
    if (shouldClear(lastActiveUid: last, currentUid: currentUid, dirty: dirty, forceClear: forceClear)) {
      await cacheGate.clearPersistence();                 // completes before reconcile() returns
      await prefs.setBool('auth.firestorePersistenceDirty', false);
    }
    await prefs.setString('auth.lastActiveUid', currentUid);
  }
}
```
A `flutter_phoenix` rebirth keeps the process/Firestore client alive → barrier `clearPersistence` would throw. Only a true relaunch yields an un-started instance. iOS path deferred with iOS launch.

### 3.4 Cold-start barrier wiring (P1-1, P1-3 fixes)
- `recoverRestoredSessionIfNeeded` already returns a `bool` (swap happened, `firebase_config.dart:100-128`) — currently **discarded** at `:70-77`. Capture it.
- `ensureAnonymousSession({bool runCacheBarrier = true, SharedPreferences? prefs, FirestoreCacheGate? cacheGate})`: after the session settles, if `runCacheBarrier`, call `CacheUidBarrier(...).reconcile(currentUser!.uid, forceClear: swapped)` where `swapped` is the captured bool (true for the no-restored-user fresh-anon branch too is irrelevant — that's first sign-in, marker handles it; only the internal-error retry sets it).
- `_AuthGate.initState`/`_retry` → `ensureAnonymousSession()` (barrier on). `_authFuture` gates `SafarApp` (`main.dart:118,129-150`) → clear precedes first read.
- **P1-1 fix:** `signOutCurrentDevice` no longer mints in-session (see §3.5); if any path still needs `ensureAnonymousSession` in-session, it passes `runCacheBarrier:false` so `clearPersistence` never runs on a started instance.

### 3.5 In-session swap flows (P1-1, P1-2, P2-1 fixes)
All three engage the overlay FIRST so no cached financials render during the swap, regardless of await duration:
- **`signOutCurrentDevice`** (`:303-324`): `controller.engageIsolation()` → `waitForPendingWrites(5s)` → set dirty → `signOut()` → `controller.restart()`. **Drop** the `_anonymousSessionFactory()` call (P2-1) — the restart's cold boot mints the new anon + clears.
- **`deleteAccount`** (`data_deletion_service.dart:32-51`): `controller.engageIsolation()` → `await _deleteAccountCallable()` (existing, server cascade) → set dirty → `signOut()` → `controller.restart()`. Replaces the navigate-home flow (P2-1).
- **`completeRecovery`** (`:226-296`): `controller.engageIsolation()` → cleanupIntent (existing) → `waitForPendingWrites(5s)` → set dirty → `signOut()` → `signInWithEmailLink()` → **`clearPendingEmail()` + `clearInFlightOp()` (existing `:271-272` — MUST stay before restart, R3 P2-4: else the bootstrap re-reads `inFlightOp` next boot and loops)** → **`await _cleanupAnonUidArtifacts(...)` to its NATURAL terminal state, then `controller.restart()`** — NO custom cap (R4 P1-2 fix). The callable uses `httpsCallable(...).call()` with no `HttpsCallableOptions` (`firebase_functions_service.dart:15`), so the client future is bounded by the default ~70s callable timeout (returns, or throws deadline-exceeded). The server scrub runs to completion independently of the client (Cloud Functions does not abort an in-flight onCall on client disconnect; its own `timeoutSeconds<=540` bounds it), so once the request is delivered the restart cannot abort it. This is identical to main's client behavior — main fires the same bounded `call()` and the server completes regardless; v3.2 just awaits that same future under the overlay before restarting. No scrub regression on any branch (R4 P1-2 fix).
- **`RecoverScreen` pre-link sign-out (R3 P2-3, `recover_screen.dart:49`):** this off-table path signs out the anon session before *sending* a recovery link (no immediate new UID). Audit into the flow: set dirty before that `signOut()` so the eventual cold boot clears, or route it through the same isolation path. Does NOT restart (no swap yet).

### 3.6 Recovery cleanup vs restart (P1-2 fix — v3.2, the load-bearing argument)
The scrub is **server-side work**, not client work. `completeRecovery` only *invokes* it via `httpsCallable('cleanupAnonUidArtifacts').call()` (`firebase_functions_service.dart:15`, no options → ~70s client timeout); the function runs server-side up to its own `timeoutSeconds<=540` (`cleanupAnonUidArtifacts.ts:247`) and **continues to completion even if the client disconnects** (Firebase callable functions are not aborted by client disconnect). So the only thing the client must guarantee is that the **request is delivered** before the process dies — and awaiting the future (which only resolves/throws *after* the request round-trips or the 70s client deadline passes) guarantees exactly that.

- R2/R3 history: v3 killed the call at a short 15s (then 60s) client cap and restarted — that could restart *before* a slow-but-valid scrub finished, and there is no durable client retry token (`cleanupSecret` is a local var `:242`; intent doc client-unreadable `firestore.rules:148`; the function's partial-retry assumes the client still holds the secret `cleanupAnonUidArtifacts.ts:346`). 
- v3.2: **no custom cap.** Await the call's natural terminal state (≤~70s default client timeout). By then the request is long delivered; the server completes the scrub on its own clock regardless of the imminent restart. This is **byte-for-byte main's scrub outcome** — `main` fires the same `call()` (same 70s client bound) unawaited and never retries on partial failure (`:278-291` logs a breadcrumb only); v3.2 awaits that identical bounded future under the overlay, then restarts. There is no branch where v3.2 loses a scrub that main would have completed.
- #46's server backstop remains the long-term guarantee for the genuinely-interrupted case (request never delivered, e.g. offline) — **not a blocker** for v3.2, since v3.2 does not regress vs main.

### 3.7 Cache-isolation overlay (P1-1 core; R3 P2-1 ordering)
- `cacheIsolationProvider` (in-memory `StateProvider<bool>`). `controller.engageIsolation()` flips it true; never reset in-session (process restarts).
- `controller.engageIsolation()` ALSO invalidates the **leaf subscription holders directly** — `ref.invalidate(authEmailLinkBootstrapProvider)` AND `ref.invalidate(notificationServiceProvider)` (R5 P2-1): these are separate plain (non-autoDispose) providers, so invalidating only the parent `appBootstrapProvider` does NOT dispose them (`auth_email_link_bootstrap_provider.dart:101,232,243`; `notification_service.dart:18,61,150`). Without this their `uriLinkStream` / `onTokenRefresh` subscriptions + the `fcm_tokens/{uid}` write stay live during the up-to-70s recovery window. Invalidate the leaves (and `appBootstrapProvider`) to tear them down.
- `SafarApp.build`: **read `cacheIsolationProvider` FIRST and short-circuit** — `if (ref.watch(cacheIsolationProvider)) return _IsolationApp();` as the opening line, BEFORE `ref.watch(routerProvider/settingsProvider/appBootstrapProvider)` (`main.dart:176-179`). Renders the opaque "Switching account…" scaffold; covers every path uniformly (no per-await reasoning).

---

## Part 4 — Files to touch

### Add (source)
- `lib/core/services/firestore_cache_gate.dart` — `FirestoreCacheGate` + `FirebaseFirestoreCacheGate`.
- `lib/core/services/cache_uid_barrier.dart` — `shouldClear` (pure) + `CacheUidBarrier.reconcile`.
- `lib/core/services/cache_isolation_controller.dart` — `CacheIsolationController` + `PlatformCacheIsolationController` (`engageIsolation()` sets the flag AND invalidates `authEmailLinkBootstrapProvider` + `notificationServiceProvider` + `appBootstrapProvider`, R5 P2-1); `cacheIsolationProvider`.

### Edit (source)
- `lib/core/config/firebase_config.dart` — capture `recoverRestoredSessionIfNeeded`'s bool; `ensureAnonymousSession` gains `runCacheBarrier/prefs/cacheGate`; run barrier with `forceClear` after settle.
- `lib/features/auth/services/auth_recovery_service.dart` — inject `CacheIsolationController`; `signOutCurrentDevice` (drop anon mint, add isolate+dirty+restart); `completeRecovery` (isolate+dirty, await cleanup to completion, restart); update `:222-225` comment.
- `lib/features/auth/services/data_deletion_service.dart` — inject controller; isolate+dirty+restart on success; update `:17-19` comment.
- `lib/main.dart` — `SafarApp.build` reads `cacheIsolationProvider` FIRST and returns the isolation scaffold before any other `ref.watch` (R3 P2-1).
- `lib/features/auth/providers/auth_provider.dart` — `authRecoveryServiceProvider` (`:59`) + `dataDeletionServiceProvider` inject a `CacheIsolationController` built with a `ref`/container handle (R3 P2-2); add `cacheIsolationProvider` + `cacheIsolationControllerProvider`.
- `lib/features/auth/screens/recover_screen.dart` — set dirty before the pre-link `signOut()` (`:49`) (R3 P2-3).
- `pubspec.yaml` — restart dependency (validate `restart_app` vs MethodChannel at impl).

### Add (tests — RED first)
- `test/unit/cache_uid_barrier_test.dart` — `shouldClear` table (incl. `forceClear`) + `reconcile` ordering.
- `test/unit/firebase_config_cache_barrier_test.dart` — internal-error retry → `reconcile(forceClear:true)`; `runCacheBarrier:false` → gate untouched.
- Extend `auth_recovery_service_test.dart` + `data_deletion_service_test.dart` — call-order: `engageIsolation` first, dirty before `signOut`, `restart` last; recovery awaits cleanup before restart.
- `test/features/.../cache_isolation_overlay_test.dart` — `SafarApp` shows overlay when flag true.

### NOT in this PR
- `security/firestore.rules`, `functions/`, fixed-path read providers, goldens, `firebase_options.dart`.
- **P2-2** (stale `createdBy` in group settle-up `group_settle_up_screen.dart:334-339`) → separate follow-up issue.
- iOS restart path (deferred with iOS launch).

---

## Part 5 — TDD (RED → GREEN)
**`shouldClear` table:**
| lastActiveUid | currentUid | dirty | forceClear | expect |
|---|---|---|---|---|
| `null` | `Y` | false | false | no clear (first launch / upgrade — P2-3) |
| `null` | `Y` | false | **true** | **clear** (internal-error swap — P1-3) |
| `X` | `Y` | false | false | clear (drift) |
| `X` | `X` | false | false | no clear |
| `X` | `X` | true | false | clear |

**reconcile:** drift/force/dirty → `clearPersistence()` once, marker updated, dirty cleared; ordering (Completer spy) → clear completes before return.
**wiring:** internal-error retry → `forceClear:true`; `runCacheBarrier:false` → gate never called.
**swap flows (call-order recorder):** `engageIsolation` before everything; dirty before `signOut`; recovery records `clearInFlightOp`+`clearPendingEmail` AND cleanup-completion BEFORE `restart` (R3 P2-4 — prevents a next-boot recovery loop); `restart` strictly last.
**overlay:** flag true → `SafarApp` renders the isolation scaffold, not the router.
**GREEN:** implement. `flutter analyze` clean → `flutter test` green → coverage ≥ 80%.
**RD-QA (device, not CI):** real eviction; `clearPersistence`-after-`Settings` ordering; restart yields un-started instance (cold boot, not rebirth). Script: ledger as anon X → recover to Y → app restarts → X's ledger gone before network.

---

## Part 6 — Remaining device-validation unknowns (RD-QA, not plan blockers)
1. **Restart primitive (HIGH):** does the chosen `restart()` produce a genuinely un-started Firestore instance (true relaunch, not a `flutter_phoenix` rebirth)? If only rebirth is achievable, cold-start `clearPersistence` throws → fall back to in-session `terminate()`. **Validate the chosen package before merge.**
2. **clearPersistence-after-Settings ordering** on Android device/emulator (R1/R2 read: settings-only is allowed pre-call; confirm no other Firestore touch precedes the barrier on any boot path).
3. **Overlay reset:** if a `restart()` can fail/no-op on some device, the in-memory isolation flag stays true → app stuck on the scaffold. Define a fallback (e.g., a manual "Restart" button on the scaffold, or a watchdog).
4. **`firestorePersistenceDirty` durability across the restart:** the dirty write must be flushed to disk before `restart()` (SharedPreferences `setBool` is async; await it) so the cold boot sees it.
(R3 P1-2 recovery-cleanup, P1-1 window, P1-3 null-marker swap, and the 4 R3 P2s are resolved in v3.1 above — these 4 are device-checks, not spec blockers.)

---

## Part 7 — Adversarial worked example (orthogonal axis: offline money-flow)
> Anon **X** adds a 12.500 OMR expense **offline** (un-synced in the mutation queue). App killed. User recovers → **Y**. Recovery flushes (5s, offline → times out), sets dirty, swaps, awaits cleanup, restarts → cold-boot `clearPersistence()` → **X's queued write is dropped**.
A cross-UID clear is destructive to the outgoing identity's un-synced writes; the 5s flush covers the online case; offline-at-swap loss is the correct confidentiality trade. Not a `BalanceCalculator` concern (remainder → alphabetically-last, `expense_provider.dart:225-242,357-373`, untouched). The inverse is **P2-3**: §3.2 does NOT clear on a bare null marker precisely to protect the upgrade rollout's same-UID unsynced writes.

---

## Part 8 — Implementation status (2026-05-29) + divergence

**Landed on `fix/issue-45-firestore-cache-uid-barrier`** (1298 tests green, `flutter analyze` clean, CI-parity coverage 80.85% w/ goldens excluded):
- Cold-start barrier core: `firestore_cache_gate.dart`, `cache_uid_barrier.dart` (`shouldClearCache` + `reconcile` + `markFirestorePersistenceDirty`), wired into `ensureAnonymousSession` with `forceClear` from the internal-error swap-bool.
- In-session machinery: `cache_isolation_controller.dart` (seam + `cacheIsolationProvider`), `cache_isolation_controller_provider.dart` (`PlatformCacheIsolationController` + provider), `MainActivity.kt` MethodChannel `restart` (relaunch Intent + `Runtime.getRuntime().exit(0)`).
- Swap flows rewritten: `completeRecovery`, `signOutCurrentDevice`, `deleteAccount` (engage → dirty → swap → restart); `RecoverScreen` pre-link sets dirty.
- `SafarApp.build` overlay short-circuit + post-frame guard.

### Divergence from §3.5 — "once isolated, always restart (finally) + clear op-state on every exit"
**Why:** §3.5's literal *engage-first → restart-only-on-success* ordering ships a [P1] for the **common** recovery failure (expired/invalid link). Sequence: engage (overlay up, leaves torn down) → `signOut` → `signInWithEmailLink` **throws** → exception propagates with NO restart → user stranded on the `_CacheIsolationApp` splash. Worse, `inFlightOp` was never cleared, so the next cold boot's `authEmailLinkBootstrapProvider` re-dispatches `completeRecovery` on the **dead** link (`auth_email_link_bootstrap_provider.dart:148-152`) → fails → engages → strands again = **permanent loop** needing an app-data wipe.
**Fix (implemented):** after `engageIsolation()`, a `finally` GUARANTEES `restart()` and clears `pendingEmail`+`inFlightOp` on **both** success and failure. A failed swap now restarts to a clean cold boot (fresh anon, dirty cache cleared, no stale op). `deleteAccount` engages isolation **only after** the cascade succeeds, so a failed cascade stays on a clean error path (no overlay); a post-cascade `signOut` failure is non-fatal (account already deleted) and still restarts.
**Status: RE-GATE PASSED (codex, 2026-05-30, high reasoning, read actual branch files).** R1 = **FAIL (1 [P1] + 1 [P2])**: [P1] the `finally` guaranteed restart was *called* but not that it *succeeds* — a thrown/absent native channel after `engageIsolation()` propagated with the overlay still mounted and no escape (the same stranding-class §6.3 deferred but never implemented); [P2] `clearPendingEmail`/`clearInFlightOp` ran before `restart()` in one block, so a prefs throw skipped restart. R2 = **PASS (no [P1])** after the fix (commit `5c84eba`): `restart()` is now fail-safe (catches a channel failure, logs, flips `cacheIsolationRestartFailedProvider` instead of rethrowing); `_CacheIsolationApp` surfaces a manual restart affordance on that flag OR after a 6s watchdog (closes §6.3 below — both the throw and silent-no-op cases); `completeRecovery`'s `finally` clears op-state via independently-guarded steps so a prefs failure can never skip the guaranteed `restart()`. R2 confirmed all paths (recovery / sign-out / deletion) can no longer propagate a restart throw, the catch is only reachable post-engage (so it can't mask a recoverable error), the watchdog is cancelled on dispose + mount-guarded, and the affordance is self-contained (no router/financial reads). Tests RED→GREEN; full suite 1310 green; `flutter analyze` clean.

### Pre-merge gate — RD-QA (device, blocks merge; CI cannot cover)
1. **[§6.1 HIGH] Restart yields an un-started Firestore instance.** Validate `MainActivity.restartApp()` (`Runtime.getRuntime().exit(0)` + relaunch Intent) produces a genuine cold boot — script: anon X adds a ledger row → recover to Y → app restarts → X's ledger is gone *before* network. If it behaves like a rebirth, cold-start `clearPersistence()` throws → fall back to in-session `terminate()`.
2. **[§6.2] `clearPersistence`-after-`Settings` ordering** holds on a real device/emulator (no other Firestore touch precedes the barrier on any boot path).
3. **[§6.3] Overlay-reset fallback — IMPLEMENTED (re-gate R1 [P1]).** `restart()` now fails closed (catch → `cacheIsolationRestartFailedProvider`), and `_CacheIsolationApp` surfaces a manual restart affordance on that flag OR after a 6s watchdog, so neither a thrown channel nor a silent no-op can strand the user. Device-QA now only confirms the affordance is reachable and its retry relaunches on a real device (the dirty flag is already persisted pre-swap, so even a fully-failed restart still clears the cache on the next manual open).
4. **[§6.4] `firestorePersistenceDirty` durability** — the `setBool` is awaited before `restart()` (verified in code); confirm it survives the process kill on-device.
