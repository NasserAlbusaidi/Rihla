# Spec: deleteAccount server-side backstop — token revocation + audit marker + scheduled reaper (#76)

**Date:** 2026-06-05
**Surface:** Cloud Functions auth/identity (`functions/src/callables/deleteAccount.ts`), a NEW scheduled function (`functions/src/scheduled/deletionReaper.ts`), `security/firestore.rules`, `firestore.indexes.json`, `functions/src/index.ts`. **Gate mandatory** (Cloud Functions auth + new identity-mutating background job + a server-only schema collection).
**Origin:** #76 (split from #46). User chose the **full** backstop (all three parts) over the issue's "defer the reaper" guidance — building it deliberately.

---

## 1. Problem (verified against code)

`deleteAccount` (`deleteAccount.ts:610-746`, body `:619-745`) is best-effort + convergent-on-retry (#46): a partial cascade throws `internal`, preserves the Auth user, and a client retry finishes it. Three gaps remain:

1. **No token revocation.** `getAuth().deleteUser(uid)` at `:725` has no `revokeRefreshTokens` before it. The code comment at `:119-122` explicitly states the hole: a preserved user's *unexpired ID token can still authenticate* (the callable layer does not check revocation). On the **partial-failure path** (user preserved, `:712-722`) a stolen token keeps working — indefinitely, because the refresh token mints new ID tokens.
2. **No abandonment backstop.** If the client never retries after a partial failure / 540s timeout, a partially-scrubbed account persists with no server remediation. Partial failures are `logger.error`'d (`:713`) but not persisted to a queryable marker.
3. **First scheduled function.** The codebase has zero `onSchedule` functions (verified: no `functions/src/scheduled/`, no `onSchedule`/`v2/scheduler` references). This is new deploy/IAM surface (Cloud Scheduler).

## 2. Design

### 2.1 Shared cascade core (refactor)

Extract the per-uid deletion body (`deleteAccount.ts:630-744`, ending before the final `return output` at `:744`) into an exported function both the callable and the reaper call:

```ts
export interface CascadeRunResult { output: DeleteAccountOutput; complete: boolean; failureKind: 'none' | 'partialCascade' | 'authDeleteFailed'; }
export async function runAccountDeletionCascade(db: Firestore, uid: string): Promise<CascadeRunResult>
```

- Does the groups loop + fcm/joinAttempts scrub exactly as today.
- **Revokes refresh tokens early** (§2.2) and runs `deleteUser` ONLY when `cascadeFailed` is empty (unchanged gate).
- **Manages the audit marker** (§2.3): writes/updates it when `!complete`, deletes it when `complete`.
- **Does NOT throw** for the two expected incomplete outcomes — returns `complete:false` + `failureKind`. (It still propagates truly-unexpected throws.)

**`complete` / `failureKind` definition (load-bearing — `auth/user-not-found` is NOT a failure):** mirror the live handler's deleteUser branch (`:727-741`) exactly, where `user-not-found` sets `authUserDeleted=false` and **returns normally (no throw)** while a real auth error throws:
- `failureKind = 'partialCascade'` iff `cascadeFailed.length > 0` (deleteUser is never attempted — unchanged gate).
- else attempt `deleteUser`; `failureKind = 'authDeleteFailed'` **only** in the real-error `else` branch (`:730-741`). `auth/user-not-found` (`:728-729`) → `failureKind = 'none'`.
- `complete = (failureKind === 'none')`, i.e. `cascadeFailed.length === 0 && authDeleteOk`, where `authDeleteOk` is true for BOTH `deleteUser` success AND `auth/user-not-found`.

This guarantees a **fully-deleted user (or an already-gone auth record) → `complete:true` → marker deleted**, never stranded. The most common reaper input — a deletion that finished but tore the marker-delete, or any reaper re-run after success — self-heals to marker-deletion rather than looping forever. Coding `complete` as "deleteUser returned a value" would strand a marker for every user-not-found and re-process it every 24h — do NOT.

The **onCall handler** keeps auth-check + `enforceDeletionRateLimit` + `assertNoInput`, then calls the core and **re-throws to preserve the #46 client contract byte-for-byte**:
- `failureKind==='partialCascade'` → `throw new HttpsError('internal', 'Account deletion did not finish; please try again.', output)` (same as `:717-721`).
- `failureKind==='authDeleteFailed'` → `throw new HttpsError('internal', 'Account data was scrubbed, but the Auth user could not be deleted.', output)` (same as `:736-740`).
- `complete` → `return output`.

**Invariant: existing `deleteAccount.test.ts` assertions (throws `internal`, auth-user-preserved-on-partial, converges-on-retry) must stay green unchanged.** The rate limit stays callable-only (the reaper is server-initiated, not user-throttled).

### 2.2 Token revocation

In the core, **before the groups query** (after the onCall wrapper's rate-limit), best-effort:
```ts
try { await getAuth().revokeRefreshTokens(uid); }
catch (e) { logger.warn('deleteAccount revokeRefreshTokens failed (continuing)', { uid, code: (e as {code?:string}).code }); }
```
Best-effort because erasure must not be blocked by a hardening step; a failure is retried on the next attempt/reaper pass. NOT added to `cascadeFailed` (it must not flip the user-preserved/re-prompt decision). `auth/user-not-found` (reaper re-running an already-deleted user) is swallowed here.

**Honest residual (state precisely — do NOT overclaim "closes the window"):** `revokeRefreshTokens` invalidates the *refresh* token, so the client can no longer mint new ID tokens. Outstanding **ID tokens stay valid until natural expiry (≤1h)** for both Firestore-rules-gated direct access (rules don't check revocation) and callables (`onCall` doesn't check revocation — the `:121` comment). So revocation **bounds** the post-partial-failure replay window from *indefinite* (refresh forever) to *≤1h* (one ID-token lifetime); it does not retroactively kill the outstanding ID token. Full closure would require rules/callables to verify revocation — infeasible cheaply, out of scope. The reaper (§2.4) provides eventual full closure by completing `deleteUser` within the schedule window. Complementary, not redundant.

### 2.3 Audit marker — `deletionAudit/{uid}` (server-only)

Written by the core via Admin SDK (rules-bypassed). Shape:
```ts
{ uid, status: 'failed', cascadeFailed: string[], firstFailedAt: Timestamp, lastAttemptAt: Timestamp, attemptCount: number, expiresAt: Timestamp }
```
Lifecycle:
- `!complete` → upsert in a transaction (preserve `firstFailedAt`, bump `attemptCount`, refresh `lastAttemptAt` + `expiresAt = now + AUDIT_TTL_MS`):
  ```ts
  await db.runTransaction(async tx => { const prev=(await tx.get(ref)).data();
    tx.set(ref,{uid,status:'failed',cascadeFailed,firstFailedAt:prev?.firstFailedAt??now,lastAttemptAt:now,attemptCount:(prev?.attemptCount??0)+1,expiresAt:Timestamp.fromMillis(now.toMillis()+AUDIT_TTL_MS)}); });
  ```
- `complete` → `deleteDocIfExists(ref)` (clears a marker left by a prior partial attempt; harmless no-op if none).

`AUDIT_TTL_MS` default **30 days** (safety net only; the reaper normally deletes the marker on completion). Env seam `DELETE_ACCOUNT_AUDIT_TTL_MS`. `cascadeFailed` in the marker is **observability only** — the reaper does NOT depend on it (it re-queries all groups still containing uid).

**`attemptCount` is best-effort under concurrency.** The upsert is a single-doc transaction, but the 24h grace doesn't fully exclude a reaper pass overlapping a late client retry (both call the core, both upsert). The cascade itself stays correct (idempotent + Phase C transactional, #46); only `attemptCount` can under-count by one on a true overlap. That is acceptable because it is observability-only — do NOT build exactly-once counting on top of it.

Common case: partial failure writes the marker, the client retries within seconds (#46) → core completes → marker deleted. The marker only **persists** when the client abandons — exactly the reaper's input.

### 2.4 Scheduled reaper — `functions/src/scheduled/deletionReaper.ts`

```ts
export const deletionReaper = onSchedule(
  { schedule: 'every 24 hours', timeoutSeconds: 540, memory: '1GiB' },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromMillis(Date.now() - REAPER_GRACE_MS);
    const stale = await db.collection('deletionAudit').where('lastAttemptAt', '<', cutoff).limit(REAPER_BATCH).get();
    for (const doc of stale.docs) {
      try { await runAccountDeletionCascade(db, doc.id); }   // core deletes the marker on success, updates it on re-failure
      catch (e) { logger.error('deletionReaper cascade error', { uid: doc.id, error: msg(e) }); }
    }
    logger.info('deletionReaper run', { scanned: stale.size });
  });
```
- **Grace** (`REAPER_GRACE_MS`, default 24h, env `DELETION_REAPER_GRACE_MS`): only reaps markers whose `lastAttemptAt` is older than the grace window, so a client actively retrying is never double-processed. Even if it were, `processGroup` is idempotent + Phase C is transactional, so concurrent execution is safe (the #46 convergence property).
- **Batch** (`REAPER_BATCH`, default 50, env `DELETION_REAPER_BATCH`): bounds work per run; `log()` the scanned count so truncation is visible. (At launch scale the failed-marker count is ~0; the cap is a safety bound, not a real limit — stated so a future scale-up revisits it.)
- **Already-deleted user:** if the marker is orphaned (deletion completed, marker delete torn), the core runs: revoke→`user-not-found` swallowed; groups query finds nothing; `deleteUser`→`user-not-found`→`authUserDeleted:false`, no throw; `cascadeFailed` empty → `complete:true` → marker deleted. Self-heals.
- Query needs only the **default single-field index** on `lastAttemptAt` (Firestore auto-indexes; no composite). No `orderBy`.

### 2.5 Rules + TTL + export
- `security/firestore.rules`: add `match /deletionAudit/{uid} { allow read, write: if false; }` (server-only, mirrors `deletionAttempts` `:204-206`).
- `firestore.indexes.json`: append a `deletionAudit.expiresAt` `ttl:true` fieldOverride (mirrors the existing four). Reproducible-from-tree; prod TTL enablement + the scheduled-function deploy ride the backend deploy ceremony.
- `functions/src/index.ts`: `export { deletionReaper } from './scheduled/deletionReaper';` — the awk/Dart extractors (`list_expected_functions.sh`, locked by `release_workflow_gate_test.dart:588-623`) auto-include it; the test asserts the two extractors agree (no fixed list), so it stays green.

## 3. RED tests (write first)

**`deleteAccount.test.ts` (extend):**
1. **Revocation ordering:** `jest.spyOn(getAuth(),'revokeRefreshTokens')` + spy `deleteUser`; on a clean deletion assert `revokeRefreshTokens` called with uid and `revoke.mock.invocationCallOrder[0] < deleteUser.mock.invocationCallOrder[0]`.
2. **Revocation on the preserved-user path:** force a partial failure (`jest.spyOn(WriteBatch.prototype,'commit')` reject-once, per `:523-529`); assert `revokeRefreshTokens` was still called (revocation precedes the cascade).
3. **Marker on partial failure:** after the throwing partial call, `deletionAudit/{deletedUid}` exists with `status:'failed'`, `attemptCount:1`, non-empty `cascadeFailed`, `expiresAt` a Timestamp, `firstFailedAt`==`lastAttemptAt`.
4. **attemptCount increments, firstFailedAt preserved:** two partial failures → `attemptCount:2`, `firstFailedAt` unchanged, `lastAttemptAt` advanced.
5. **Marker cleared on success:** seed a pre-existing `deletionAudit/{deletedUid}`, run a clean deletion → marker absent afterward.
6. **Regression:** the existing partial/auth-fail/converge tests (`:509,556,622`) still pass unchanged (same `internal` throws, same payloads).

**`deletionReaper.test.ts` (new).** `testEnv.wrap` is typed only for v1/`CloudFunctionV2<CloudEvent>`; a v2 `onSchedule` (`ScheduleFunction extends HttpsFunction`) matches neither overload under `strict` ts-jest, so the wrap needs a cast: `const wrapped = testEnv.wrap(deletionReaper as any)` (runtime-verified that `wrap` executes the onSchedule handler body). Invoke `await wrapped()`:
7. **Finishes an abandoned deletion:** seed auth user + group still containing uid + a stale marker (`lastAttemptAt` = now−25h); run reaper → group scrubbed (uid→tombstone), auth user deleted (`getUser`→`user-not-found`), marker gone.
8. **Respects grace:** a fresh marker (`lastAttemptAt`=now) is NOT processed (auth user + group untouched, marker intact).
9. **Self-heals an orphaned marker:** stale marker but auth user already absent and no groups → reaper deletes the marker, no throw.
10. **Re-failure keeps the marker:** stale marker + a forced cascade failure → marker persists with `attemptCount` incremented, auth user preserved.
11. **Batch cap:** `DELETION_REAPER_BATCH=1` with two stale markers → exactly one processed per run.

## 4. Out of scope (do not bundle)
- Changing the #46 client contract / partial-failure UX (client already handles throw-vs-resolve).
- Making Firestore rules or callables verify token revocation (infeasible cheaply; the ≤1h residual is documented).
- Receipt/Storage object deletion (`:22` TODO — no upload flow yet).
- Backfilling markers for historically-abandoned deletions (none known; the reaper only acts on markers the new code writes).

## 5. Verification principles applied
- **#1 callsite classification:** the cascade core is OUTBOUND (mutates Firestore + Auth identity); the marker is BOTH (written by core, read by reaper) — both consumers named (§2.3/§2.4).
- **#2 claims vs code:** `deleteUser` at `:725` has no preceding revoke; `:119-122` documents the revocation gap; no `onSchedule` anywhere; `release_workflow_gate_test.dart:622` asserts extractor-equality not a fixed list — all re-verified this session.
- **#3 one read-path per write-path:** the `deletionAudit` marker's reader is the reaper (`deletionReaper.ts`), named. The revoked-token's "reader" is Firestore rules/callable auth — analyzed (the ≤1h residual).
- **#4 enumerate fields from the type:** `DeleteAccountOutput` (`:38-53`) is unchanged; the new `deletionAudit` doc fields are enumerated exhaustively in §2.3.
- **#5 data contracts:** exact `CascadeRunResult` shape, exact marker keys/types, exact reaper query.
- **#6 decomposition:** the core's `complete` flag = `cascadeFailed.length===0 && authDeleteOk`, where `authDeleteOk` is true for deleteUser success **AND** `auth/user-not-found` (the live handler's non-throwing branch, `:727-741`). Spelled out so a fully-deleted/already-gone user → `complete:true` → marker deleted, never stranded (§2.1).
- **#7 adversarial / orthogonal axis:** the fix is on the identity-deletion axis; adversarial cases exercise **time** (grace window, the reaper vs an active client retry race → idempotency) and **identity** (orphaned marker for an already-deleted user → self-heal) — §2.4.
