# Spec — #213: anon session `internal-error` recovery destroys the account

**Status:** IMPLEMENTED — Gate PASS (no P1s), RED→GREEN, full suite green
**Date:** 2026-06-02
**Severity:** P0 — total data loss for no-email anon users

> Line numbers below are **pre-fix** — they document the starting state; ranges shift
> after dropping two params and adding `verifyTokenOverride`.

## Problem (verified against code, not the issue text)

`FirebaseConfig.recoverRestoredSessionIfNeeded` (`lib/core/config/firebase_config.dart:147-176`)
runs at bootstrap from `ensureAnonymousSession` (`:88-94`). It calls `getIdToken()`
on the restored user; on **any** `FirebaseAuthException(code: 'internal-error')` it:

```dart
await signOut();            // destroys the anon credential (unrecoverable for no-email anon)
await signInAnonymously();  // mints a NEW uid → orphans all data under the old uid
return true;                // swapped=true
```

`swapped` is the **only** input to `_runCacheBarrier(forceClear: swapped)` (`:128`),
which calls `CacheUidBarrier.reconcile(uid, forceClear: true)` →
`shouldClearCache(... forceClear: true)` → `clearPersistence()` wipes the on-device
Firestore cache (`cache_uid_barrier.dart:22-28,53-67`).

**Why it's wrong:** `internal-error` is the Firebase SDK's catch-all for *transient*
failures during a token **refresh**. `getIdToken()` (no `forceRefresh`) returns the cached
token without a network call when it's unexpired, so the credible trigger here is **App
Check / Play Integrity rejection** (release-only, `firebase_config.dart:43-50`) or a
backend/network failure when the SDK *does* refresh — not mere token staleness. Whatever
the trigger, a perfectly healthy anon account that couldn't complete one token refresh is
**permanently abandoned**. For an anon user with no linked email, the old UID is
unrecoverable → effectively permanent data loss.

Confirmed downstream: the **only** consumer of the `swapped=true` return is the
cache-barrier `forceClear`. No other code path depends on the swap (grep: `recoverRestoredSessionIfNeeded`,
`forceClear`, `swapped`). The in-session swap paths use the dirty *flag*
(`markFirestorePersistenceDirty`), not `forceClear` — they are unaffected.

## Original intent (git `2cf64ac`, 2026-05-11)

Added as a "release readiness fix" to stop the app getting stuck on a restored session
whose token wouldn't verify. The fear: a corrupt restored token leaves the app unable to
authenticate. The chosen remedy (discard + mint fresh) traded "stuck" for "silent
irreversible data loss" — and `internal-error` does not actually mean "corrupt".

## Decision: never discard a restored anonymous session from this path

The asymmetry that justifies "never discard":

| Case | OLD behavior | NEW behavior |
|---|---|---|
| **False positive** — transient `internal-error`, account is LIVE | catastrophic irreversible loss | harmless: session kept, SDK refreshes token lazily once online/App-Check recovers |
| **True positive** — account genuinely dead server-side | mint fresh, user starts over | proceed with old UID, reads denied, user starts over by creating new data (dead UID's data was already gone) |

"Never discard" **strictly dominates**: it removes the catastrophe and the dead-account
case is no worse. There is **no** `getIdToken()` error code for which destroying an anon
credential at bootstrap is the right move — codes that mean the account is truly gone
(`user-disabled`, `user-not-found`) already returned `false` (no swap) under the old code.

**Does keeping a stale-token session hang the app?** No. `ensureAnonymousSession` awaits
`authStateChanges().first` (resolves with the restored user), then the catch returns fast
(no throw), then the barrier does not clear (same UID). `_authFuture` completes → `SafarApp`
renders. Token staleness manifests only as later denied Firestore ops, which the SDK
handles via offline persistence (cached reads + queued writes) and a lazy refresh on
reconnect. The UID is preserved throughout.

## The fix (behavioral + remove the destructive capability)

`recoverRestoredSessionIfNeeded` **drops** the `signOut`/`signInAnonymously` parameters
entirely (Gate P1-2: leaving the discard capability wired into the very function whose
contract is "never discard" re-arms the exact regression — removing it IS the fix, not a
separable refactor). The function verifies the restored token and records the result; both
branches return `false`. It can no longer sign out or mint a UID.

```dart
@visibleForTesting
static Future<bool> recoverRestoredSessionIfNeeded({
  required Future<void> Function() verifyToken,
}) async {
  try {
    await verifyToken();
    log('Firebase restored session token verified');
    return false;
  } on FirebaseAuthException catch (e, stackTrace) {
    // #213: NEVER discard a restored anonymous session. Any failure here is
    // transient/ambiguous (App Check rejection, network/backend hiccup during
    // refresh); signing out would mint a new UID and irreversibly orphan an
    // anon user's data. Keep the session — the SDK refreshes the token lazily
    // once connectivity/App Check recovers, and Firestore offline persistence
    // serves cached reads meanwhile. Record the failure only.
    log(
      'Firebase restored session token check failed (session kept): '
      '${e.code} — ${e.message}',
      error: e,
      stackTrace: stackTrace,
    );
    return false;
  }
}
```

`ensureAnonymousSession` stops passing those two closures. It keeps `swapped` /
`forceClear: swapped` (now always `false`) — the **barrier `forceClear` plumbing is the
one genuinely-separable cleanup** (it has its own signature + dedicated tests) and is
deferred (Gate confirmed). After this fix nothing produces `forceClear: true`.

### Totality / `_AuthGate` interaction (Gate P2-2)

Post-fix `recoverRestoredSessionIfNeeded` is **total** — the `FirebaseAuthException`
branch cannot rethrow, so `_authFuture` always completes and `_AuthGate`'s error/retry
branch (`main.dart:146`) is unreachable via this path. Today `signInAnonymously()` *can*
rethrow (`firebase_config.dart:143`) → surfaces the retry screen. Removing the re-mint
removes that escape hatch **by design** — the bug *was* that escape hatch firing
destructively. The "no persisted session" path (`:97`) still re-mints legitimately and
can still surface the retry screen if first sign-in genuinely fails.

### Test seam for the end-to-end test (Gate P1-1)

`firebase_auth_mocks`' `MockUser.getIdToken` cannot be made to throw, so an `internal-error`
cannot be driven through the real `ensureAnonymousSession` → `restoredUser.getIdToken()`
path — a naive end-to-end test would pass vacuously. Add a test-only seam:

```dart
static Future<void> ensureAnonymousSession({
  bool runCacheBarrier = true,
  FirebaseAuth? authOverride,
  SharedPreferences? prefs,
  FirestoreCacheGate? cacheGate,
  @visibleForTesting Future<void> Function(User restoredUser)? verifyTokenOverride,
}) async {
  ...
  swapped = await recoverRestoredSessionIfNeeded(
    verifyToken: () => verifyTokenOverride != null
        ? verifyTokenOverride(restoredUser)
        : restoredUser.getIdToken().then((_) {}),
  );
}
```

This lets the integration test force `internal-error` through the real barrier path and
assert UID-unchanged + `clearCount == 0` for real.

## Out of scope (follow-ups, named so they're not Schrödinger fixes)

- **Dead-plumbing cleanup** — remove the `forceClear` param chain
  (`ensureAnonymousSession` → `_runCacheBarrier` → `reconcile` → `shouldClearCache`) now
  that its only producer is gone, and collapse the always-`false` `swapped`/bool return.
  Separate refactor PR (it touches the barrier's dedicated tests). The destructive
  `signOut`/`signInAnonymously` closures are removed **in this PR**, not deferred.
- **P1 — push email-link recovery hard at onboarding for anon users** (the only real
  safety net). Separate feature.
- **P2 — Sentry instrumentation** of the kept-session branch (capture the wrapped cause to
  quantify real-world frequency). Additive; deferred so the hotfix stays test-simple.
- **Admin rescue of the specific affected group** (re-key data to the user's new UID).

## TDD plan

**RED** — flip the existing pinning test
`test/integration/firebase_auth_test.dart:86-111`
(`'internal-error during restored token check starts a fresh session'`). Because P1-2
removes the `signOut`/`signInAnonymously` params, **delete the `signOut:`/`signInAnonymously:`
named args and the `didSignOut`/`didSignIn` vars** (the old callsite won't compile against
the new signature) — the "no discard" guarantee is now **structural** (the function has no
capability to sign out), so the assertion reduces to `expect(recovered, isFalse)`. Coverage:

1. `internal-error` from `verifyToken` → `recovered == false` (the core regression — would
   have caught #213).
2. a non-`internal-error` code (e.g. `network-request-failed`) → also `recovered == false`.
3. healthy token (no throw) → `recovered == false` (keep existing healthy-path coverage).
4. integration via `ensureAnonymousSession` **using the `verifyTokenOverride` seam** to
   force an `internal-error`: a restored user keeps the **same** UID, the gate is **not**
   cleared (`clearCount == 0`), and `lastActiveUid` is unchanged. This is the test that
   would catch a re-regression where someone re-wires the swap; it is real (not vacuous)
   only because of the seam.

**GREEN** — apply the branch change above.

**Verify** — `flutter analyze` clean; run `test/integration/firebase_auth_test.dart`,
`test/unit/firebase_config_cache_barrier_test.dart`, `test/unit/cache_uid_barrier_test.dart`,
then the full suite. Confirm 80% gate unaffected.

## Docs to update with the fix

- `CLAUDE.md` Bootstrap Order line — currently describes the destructive behavior as a
  feature ("retries on internal-error for corrupted restored sessions"). Rewrite to match
  new code.
- Memory `project_anon_internal_error_dataloss_213.md` — mark fixed once merged.
