# Plan — #73: soft App Check + invocation rate limit on `deleteAccount`

**Issue:** #73 (P0, compliance/security) — App Check blocks account deletion on
attestation-failing Android devices (Play Integrity failure / no Play Services /
MDM) → GDPR right-to-erasure block. Split out of #46.

**Approach (locked via brainstorm 2026-05-29):** soft App Check + per-UID rate
limit. Rejected: separate fallback callable (its "stronger auth" excludes the
anon-only users who are the blocked population; and a non-attested fallback has
the *same* abuse surface as a soft primary path, just with more code) and
signed-link (email-linked only).

> **v2 — revised after Gate round 1 (codex, 2026-05-29).** Round 1 found [P1]s
> that broke v1's rate-limit design (see "Gate" below). The limit is now
> **invocation-counting**, run **before** the cascade, with a **Firestore TTL**
> reaping the counter — not failure-counting with manual cleanup.

## Scope

**In:**
1. `functions/src/callables/deleteAccount.ts`: `enforceAppCheck: true` →
   `enforceAppCheck: false` (token still verified-if-present; missing/failed
   attestation no longer hard-rejects). `request.auth` stays required.
2. A per-UID **invocation** rate limit run as the **first** step (after the auth
   + `assertNoInput` guards, before the cascade): transactionally check-and-
   increment `deletionAttempts/{uid}`; throw `resource-exhausted` when the
   in-window count is at the limit. The counter is **never mutated again** by the
   handler — the existing cascade and its error surface stay byte-identical.
3. **Firestore TTL** on `deletionAttempts.expiresAt` so counter docs self-reap
   (one `gcloud` command + an `expiresAt` field on each write). This is this
   feature's own hygiene and is **distinct** from #46's `recoveryCleanupIntents`
   TTL (different collection, different strand).
4. `security/firestore.rules`: deny all client access to `deletionAttempts`
   (server-only, exactly like `joinAttempts`).
5. Tests: rate-limit rejection + counter shape/TTL field (Jest emulator); a rules
   test denying client access to `deletionAttempts`; add `deletionAttempts` to the
   test cleanup helpers.

**Out (explicitly):**
- `cleanupAnonUidArtifacts` App Check stays `true` — recovery-migration path
  (bearer-secret-gated `oldUid`→`newUid`), a different threat model. Relax
  separately if ever needed.
- Making the static `/delete-data` web page (`hosting/index.html`) a working
  authenticated deletion flow — in-app deletion now works on any device, which
  closes the GDPR hole. Follow-up only.
- #46's resumability driver (PR-B) and `recoveryCleanupIntents` TTL — separate
  strands.

## Verified current state (`main` @ HEAD, read 2026-05-29)

- `deleteAccount` is **self-scoped**: `deleteAccount.ts:484-489` — rejects when
  `!request.auth`, `assertNoInput(request.data)` (def `:82`) forbids any payload,
  `uid = request.auth.uid`. Caller can only ever delete **their own** account.
  (Confirmed by Gate round 1: no client-supplied UID path.)
- Options today: `deleteAccount.ts:482` `{ enforceAppCheck: true, timeoutSeconds:
  540, memory: '1GiB' }`. `cleanupAnonUidArtifacts.ts:254` identical; not touched.
- Auth model caveat (Gate round 1, [P1]): the v2 callable layer verifies the ID
  token signature/expiry but does **not** check revocation, so a deleted user's
  **unexpired ID token (≤1h) still authenticates**. v1's "the session is invalid
  after auth-deletion, so it self-terminates" assumption was **false** and is the
  reason the limit must count invocations, not failures.
- Rate-limit precedent — `joinGroupByInviteCode.ts:23-25`: `JOIN_ATTEMPT_LIMIT =
  5`, window/lock `= 60*60*1000`; `joinAttempts/{uid}` `{ failCount, firstFailAt,
  lockedUntil }`; `assertJoinNotLocked` (`:132`) + `recordFailedJoinAttempt`
  (`:147`) — but that is **failure**-counting for invite-code guessing; deletion
  is **not** guess-and-check, so we count invocations instead (do **not** claim a
  verbatim mirror — Gate round 1 [P2]).
- Rules precedent — `firestore.rules:144-146`: `match /joinAttempts/{userId} {
  allow read, write: if false; }`.
- Test harness — `deleteAccount.test.ts` uses `firebase-functions-test`
  `testEnv.wrap(deleteAccount)`; `wrapped({ data, auth })` calls `cloudFunction.run`
  directly, and v2 `onCall` puts App Check enforcement in the HTTP wrapper, **not**
  `run` — so `wrap` **cannot** exercise `enforceAppCheck` (confirmed by Gate round
  1). Current cleanup clears only `fcm_tokens` + `joinAttempts` (`:24`); fixtures
  clear `joinAttempts` + `recoveryCleanupIntents` (`fixtures.ts:46`) — both must
  add `deletionAttempts`.

## Threat-model argument (honest version, post-Gate)

App Check proves a call came from the genuine app binary — defense-in-depth
against scripted/non-genuine-app access to a callable. `deleteAccount` can only
delete the **caller's own** account, and `request.auth` (a valid Firebase token)
stays required, so relaxing App Check opens **no cross-user or privilege-
escalation vector** (Gate-verified self-scope). What it *does* open is a
**scripted-invocation cost/DoS vector**: a script with a valid anon token can call
repeatedly (within the token's ≤1h life), and can rotate anon UIDs.

- **Per-UID hammering** (same token, repeated calls) → bounded by the invocation
  rate limit (`DELETION_ATTEMPT_LIMIT` per rolling hour per UID).
- **Cross-UID rotation** (mint anon UID → call → mint another) → **inherent
  residual** of supporting attestation-failing devices; **no** per-UID limit can
  close it. Bounded instead by (a) Firebase Identity Platform anonymous sign-up
  quotas (configurable per project) and (b) the near-zero cost of an empty-cascade
  call (one indexed `array-contains` query returning ~0 docs + a fast
  `user-not-found`). We **accept and document** this residual rather than claim the
  limit fully compensates (Gate round 1 [P1] #2). If abuse is ever observed, the
  escalation is to re-enable App Check and add a narrowly-scoped non-attested
  fallback, or tighten anon sign-up quotas.

## Proposed change — `functions/src/callables/deleteAccount.ts`

Constants + a single transactional helper near the top:

```ts
const DELETION_ATTEMPT_LIMIT = 5;
const DELETION_ATTEMPT_WINDOW_MS = 60 * 60 * 1000;

function isTimestamp(v: unknown): v is Timestamp { return v instanceof Timestamp; }

// #73: deletion is self-scoped, so App Check is relaxed (enforceAppCheck:false)
// to unblock GDPR erasure on attestation-failing devices. This per-UID invocation
// limit is the compensating control for the scripted-call cost vector. It counts
// EVERY invocation (success, no-op, or failure) because a deleted user's unexpired
// ID token can still authenticate (no revocation check at the callable layer), so
// failure-counting would not bound replays. `expiresAt` drives a Firestore TTL so
// the counter doc (a short-lived pseudonymous marker keyed by UID, no profile
// data) self-reaps — no manual cleanup, no orphan keyed by a deleted UID.
async function enforceDeletionRateLimit(db: Firestore, uid: string): Promise<void> {
  const ref = db.doc(`deletionAttempts/${uid}`);
  await db.runTransaction(async (tx) => {
    const now = Timestamp.now();
    const data = (await tx.get(ref)).data() ?? {};
    const windowStart = data.windowStart;
    const inWindow = isTimestamp(windowStart)
      && now.toMillis() - windowStart.toMillis() < DELETION_ATTEMPT_WINDOW_MS;
    const count = inWindow && typeof data.count === 'number' ? data.count : 0;
    if (count >= DELETION_ATTEMPT_LIMIT) {
      throw new HttpsError('resource-exhausted', 'Too many deletion attempts. Try again later.');
    }
    const nextWindowStart = inWindow ? (windowStart as Timestamp) : now;
    tx.set(ref, {
      count: count + 1,
      windowStart: nextWindowStart,
      expiresAt: Timestamp.fromMillis(nextWindowStart.toMillis() + DELETION_ATTEMPT_WINDOW_MS),
    }, { merge: true });
  });
}
```

Option change + one inserted line; **everything else in the handler is untouched**:

```ts
export const deleteAccount = onCall<unknown, Promise<DeleteAccountOutput>>(
  // #73: soft App Check (verify-if-present) so attestation-failing devices can
  // exercise GDPR erasure; per-UID invocation rate limit is the compensating
  // control. See enforceDeletionRateLimit + plan docs/plans/2026-05-29-issue-73-*.
  { enforceAppCheck: false, timeoutSeconds: 540, memory: '1GiB' },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign-in required.');
    const uid = request.auth.uid;
    const db = getFirestore();
    await enforceDeletionRateLimit(db, uid);   // NEW — throttle before assertNoInput + cascade
    assertNoInput(request.data);               // (order vs limiter swapped: count malformed calls too)
    // ... existing cascade, writer.flush(), fcm/joinAttempts deletes,
    //     getAuth().deleteUser block, and `return output` — ALL UNCHANGED ...
  },
);
```

Why this resolves the round-1 [P1]s:
- **Replay after deletion / no-op success (P1 #1):** every invocation increments
  up-front, so replays with an unexpired token hit `resource-exhausted` after the
  limit. The "self-terminating" claim is dropped.
- **No orphan, no error-masking (P1 #3 + P2):** the counter is written once per
  call and never cleaned by the handler, so there is no cleanup step to fail or to
  mask the cascade error; the existing `getAuth().deleteUser` catch
  (`HttpsError('internal', …, output)` / `authUserDeleted:false` on
  `user-not-found`) is **byte-identical**. The counter doc is a short-lived
  pseudonymous marker (keyed by UID, no profile data) and is TTL-reaped within ~1h
  of its window start.
- **Compensating-control honesty (P1 #2):** documented above as a bounded,
  accepted residual, not a claim of full compensation.

## Proposed change — `security/firestore.rules`

Insert after the `joinAttempts` block (`:146`):

```
match /deletionAttempts/{userId} {
  allow read, write: if false;
}
```

Admin SDK bypasses rules; clients denied (read/list/write). Subcollections stay
denied by the recursive default-deny.

## Firestore TTL (ops)

Enable a TTL policy on the `expiresAt` field of the `deletionAttempts` collection
group (so counter docs self-delete ~1h after their window starts):

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=deletionAttempts --enable-ttl --project=rihla-safar
```

Document in the PR body; TTL is best-effort (Firestore deletes within ~24h of
`expiresAt`), which is fine — the rate-limit logic already treats out-of-window
counters as reset, so a late reap never affects correctness.

## Test plan

**`functions/test/callables/deleteAccount.test.ts`** (Jest, emulator):
- **Rate-limit rejection:** drive 5 successful deletions/ no-ops for one UID within
  the window (or pre-seed `deletionAttempts/{uid}` with `{ count: 5, windowStart:
  now }`), then the next `wrapped({ data:{}, auth:{uid} })` rejects
  `resource-exhausted`; assert the cascade did **not** run (a still-present group
  for that uid is untouched).
- **Counter shape + TTL field:** after a normal deletion, `deletionAttempts/{uid}`
  exists with `count >= 1` and an `expiresAt` Timestamp ≈ `windowStart + 1h`.
- **Window reset:** pre-seed `{ count: 5, windowStart: now-2h }`; next call
  succeeds (stale window resets to count 1).
- Existing 4 tests stay green — the handler body is unchanged apart from the
  up-front limit call (which a fresh UID passes).
- Add `deletionAttempts` to `clearGlobalDocs` (`:24`) and `fixtures.clearFirestore`
  so rate-limit state doesn't leak across tests (Gate round 1 [P3]).
- **Honest gap:** `enforceAppCheck: false` is not exercisable via `testEnv.wrap`
  (it bypasses App Check — Gate-verified). No test asserts the flag; verified by
  Gate + review.

**`functions/test/firestore-rules-publish-readiness.test.ts`** (emulator rules):
- `deletionAttempts` denied to clients — mirror the `joinAttempts` deny test
  (`get`/`list`/`set` all `assertFails`).

## Verification

```bash
npm --prefix functions run build
npm --prefix functions run test:emulator     # Java 21 + emulator
```
No Flutter changes (Functions + rules + TTL only) → no `flutter analyze` impact.
No ESLint configured in `functions/` (tracked separately in #55).

## Gate

Touches **Cloud Functions auth** *and* **`security/firestore.rules`** → two Gate
categories. `/codex` fresh-context review **mandatory before any edit**
(Operating Contract). Apply findings, re-run, stop when no [P1].

**Round 1 (codex, 2026-05-29, high reasoning) — verdict: do not implement as
written; 3×[P1].** Findings + resolutions:
- [P1] failure-counting + "self-terminating session" assumption is wrong (deleted
  user's unexpired ID token still authenticates; no revocation check) → **switched
  to invocation-counting, run up-front.**
- [P1] failure-counting is not a compensating control (no-op successes uncounted;
  UID rotation) → **invocation-counting bounds per-UID; cross-UID residual now
  documented honestly, not claimed-away.**
- [P1] on-success counter cleanup can orphan a doc keyed by a deleted UID / mask
  the error → **counter is never cleaned by the handler; Firestore TTL reaps it;
  cascade/error surface untouched.**
- [P2] error-masking if accounting throws → **resolved structurally (no
  post-cascade accounting).**
- [P2] "mirrors joinGroupByInviteCode" overstated → **described accurately as
  invocation-counting, not a mirror.**
- [P3] tests must clear `deletionAttempts` → **folded into the test plan.**
- Verified-good: self-scope, rules deny block, `testEnv.wrap` testability claim.

**Round 2 (codex, 2026-05-29, high reasoning) — verdict: zero [P1]s; safe to
implement as the GDPR erasure fix.** All round-1 [P1]s confirmed resolved
(invocation-counting bounds the replay loop — attempts 2-5 no-op, 6th throws
`resource-exhausted` before querying groups or Auth; no cleanup step so no
orphan/error-masking; error surface byte-identical; transaction serialization
sound; stale windows reset correctly). Remaining, folded in without a re-gate:
- [P2] describe `deletionAttempts/{uid}` as a short-lived pseudonymous marker
  (doc ID is the UID), not "non-PII" → **reworded above.**
- [P2] limiter ran after `assertNoInput`, so malformed authenticated calls weren't
  counted → **moved the limiter before `assertNoInput`.**
- [P3] TTL is an ops step that could be missed → **explicit deploy-checklist item
  below.**

**Status: PASSED (no [P1] after round 2). Clear to implement.**

## Deploy checklist (compliance-critical — do not skip)

- [ ] Code + tests merged.
- [ ] `gcloud firestore fields ttls update expiresAt --collection-group=deletionAttempts --enable-ttl --project=rihla-safar` run and confirmed (`gcloud firestore fields ttls list` shows it active). **If skipped, counter docs persist** — not a handler bug, but defeats the orphan-reaping.
- [ ] `firebase deploy --only functions:deleteAccount,firestore:rules` (App Check relaxation + rules deny live together).
- [ ] Manual: confirm in-app deletion succeeds on an attestation-failing device (rooted/emulator/no-Play-Services) — the actual fix.

## Execution order (after Gate clears)

1. Add rules deny test + `deletionAttempts` rate-limit/TTL-field tests; update test
   cleanup helpers.
2. `deleteAccount.ts`: constants + `enforceDeletionRateLimit` + soft App Check +
   the single up-front call.
3. `firestore.rules`: add the `deletionAttempts` deny block.
4. `npm --prefix functions run build` + `test:emulator` green.
5. Enable the Firestore TTL policy (record the `gcloud` command in the PR body).
6. Commit `fix(auth): soft App Check + invocation rate limit on deleteAccount (#73)`.
