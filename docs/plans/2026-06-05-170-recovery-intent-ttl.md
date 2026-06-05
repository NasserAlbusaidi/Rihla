# Spec: Firestore TTL on `recoveryCleanupIntents.expiresAt` (#170)

**Date:** 2026-06-05
**Surface:** `security/firestore.rules` (`validCleanupIntent`) + client write path (`auth_recovery_service.dart`) + `firestore.indexes.json` TTL declaration. **Gate mandatory** (rules + a schema/field-name change with both a read-path and a write-path).
**Origin:** #170 (split from #131; the `deletionAttempts` half shipped as #167). Milestone: Post-launch hardening (trust boundary).

---

## 1. Problem (verified against code, not docs)

`recoveryCleanupIntents/{oldUid}` holds a 32–128-char bearer secret. It is client-deny on `get/list/delete` (`firestore.rules:231`), so the **only** possible reaper is a server-side Firestore TTL. No TTL exists for this collection (`firestore.indexes.json` declares `expiresAt` TTL for `deletionAttempts`, `deleteGroupAttempts`, `_writeCounters` only — `recoveryCleanupIntents` absent). The collection carries only `{secret, createdAt}` — **no `expiresAt` field for a TTL to key on.** Result: abandoned/expired intents accumulate indefinitely at public scale.

**Not an open exploit window.** The 15-min validity is enforced server-side off `createdAt` in `cleanupAnonUidArtifacts.ts:196-202` (`Timestamp.now() - createdAt > cleanupIntentMaxAgeMs`, `cleanupIntentMaxAgeMs = 15*60*1000` at :31), and the happy path code-deletes the intent. This is **unbounded growth of dead docs**, a privacy/hygiene issue (P2), not a live secret-replay hole.

**Why it is not a one-line TTL** (verified):
- TTL must key on `expiresAt`; the field does not exist on the write. A TTL on `createdAt` would reap at creation and break the 15-min validity window.
- `validCleanupIntent()` (`firestore.rules:220-228`) pins the shape to **exactly** `{secret, createdAt}` via `keys().hasOnly([...])` plus per-field `is` checks. Adding `expiresAt` to the write WITHOUT relaxing `hasOnly` makes the rule **reject every new intent** (extra key) — which would silently disable recovery cleanup. So the rule and the client must change together.

## 2. Callsite classification (Verification principle #1)

`recoveryCleanupIntents/{oldUid}` data flow, every site classified:

| Site | File:line | Direction | Reads/writes |
|---|---|---|---|
| Client intent factory | `auth_recovery_service.dart:65-75` | **OUTBOUND** (write) | sets `{secret, createdAt}` — **add `expiresAt` here** |
| Rules create/update gate | `firestore.rules:220-230` | gate on OUTBOUND | `validCleanupIntent()` — **admit + constrain `expiresAt`** |
| Server validity check | `cleanupAnonUidArtifacts.ts:181-204` | **INBOUND** (read) | reads `secret`, `createdAt`; **ignores `expiresAt`** — unchanged |
| Server fixture writes | `cleanupAnonUidArtifacts.test.ts:43` | test write (Admin SDK, rules-bypassed) | `{secret, createdAt}` — unaffected; optional realism only |
| Rules emulator test | `firestore-rules-publish-readiness.test.ts:381-405` | tests OUTBOUND gate | **update for new shape** |
| TTL config | `firestore.indexes.json` fieldOverrides | infra (GC) | **add `recoveryCleanupIntents.expiresAt` override** |

**One read-path per write-path (principle #3):** "who reads `expiresAt` after the client writes it?" → the **Firestore TTL service** (server-side GC), and **nobody else**. The server validity logic deliberately does NOT read `expiresAt` — validity stays keyed on `createdAt` (the security control). `expiresAt` is a pure GC marker. This separation is load-bearing: it means `expiresAt` can be set generously (longer than validity) without weakening the 15-min window.

## 3. Design

### 3.1 Client (`auth_recovery_service.dart`)

The factory currently writes (`:71-74`):
```dart
.set({
  'secret': secret,
  'createdAt': FieldValue.serverTimestamp(),
});
```
`createdAt` is a server-timestamp sentinel; the client cannot do arithmetic on it. So `expiresAt` is a **client-computed** concrete `Timestamp`:
```dart
'expiresAt': Timestamp.fromDate(
  clock().toUtc().add(_cleanupIntentTtl),
),
```
with `static const _cleanupIntentTtl = Duration(hours: 24);`.

**Why 24h, not ~15min (non-obvious — document):** `expiresAt` becomes the TTL *eligibility* time. It MUST exceed `createdAt + validity(15min) + worst-case client clock skew`, or a TTL could reap an intent that is still valid server-side and break a legitimate recovery. The client computes `expiresAt` from its **own** clock, while the 15-min validity is checked server-side off `createdAt`. A client clock running *behind* by `S` minutes yields `expiresAt = realNow + 24h − S`; reaping stays after the 15-min window for any `S < 24h − 15min`. 24h dwarfs any realistic skew; the storage saving of a 1h vs 24h window on a tiny pseudonymous doc is negligible. (TTL deletion itself is best-effort and may lag up to ~72h regardless — `expiresAt` is the earliest-eligible instant, not a guaranteed delete time.)

**Testability seam:** the write happens inside the default `_cleanupIntentFactory` closure, which no Dart test exercises (all inject a stub). Extract the map construction into a pure, `@visibleForTesting` builder so the field set is unit-testable without driving the full `completeRecovery` flow:
```dart
@visibleForTesting
static Map<String, Object?> buildCleanupIntentPayload(
  String secret, {
  DateTime Function()? clock,
}) {
  final now = (clock ?? DateTime.now)();
  return {
    'secret': secret,
    'createdAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(now.toUtc().add(_cleanupIntentTtl)),
  };
}
```
The factory calls `buildCleanupIntentPayload(secret)`. (This is the minimum seam #170 needs to be testable — not opportunistic refactoring.)

**Failure behavior is already graceful (verified `:259-270`):** a thrown intent write is caught, `cleanupSecret` stays `null`, the later cleanup callable is skipped (`:293-296`), and recovery still succeeds. So even if a stricter rule rejected an edge write, recovery degrades to "no cleanup," never breaks. This lowers the risk of value-domain rule constraints.

### 3.2 Rules (`firestore.rules:220-228`)

```
function validCleanupIntent() {
  return signedIn()
    && request.auth.uid == oldUid
    && request.resource.data.keys().hasOnly(['secret', 'createdAt', 'expiresAt'])
    && request.resource.data.secret is string
    && request.resource.data.secret.size() >= 32
    && request.resource.data.secret.size() <= 128
    && request.resource.data.createdAt is timestamp
    && request.resource.data.expiresAt is timestamp
    && request.resource.data.expiresAt > request.resource.data.createdAt;
}
```

Three changes, each justified:
1. `hasOnly([... 'expiresAt'])` — admit the new key (still caps the upper bound: no other extra keys).
2. `expiresAt is timestamp` — **enforces presence + type.** A missing field fails `is timestamp`, so every accepted intent carries a TTL key. This is the load-bearing line that closes the issue (guarantees the TTL can engage for all new intents).
3. `expiresAt > createdAt` — sanity lower bound. `createdAt` is written via `serverTimestamp()`, which the rules engine resolves to `request.time`; in the emulator test `createdAt` is a concrete `new Date()`. In both cases this rejects a past/zero `expiresAt` that would make the TTL reap a fresh intent immediately (a foot-gun guard). Our client's `now + 24h` satisfies it with ~24h of slack.

**Rejected alternative — an explicit upper bound** (`expiresAt < request.time + duration.value(N,'d')`): would cap a "set `expiresAt` to year 3000 to defeat the TTL on my own doc" abuse, but (a) introduces `request.time`/`duration` syntax **not currently used anywhere in this rules file** (novel surface to get wrong), (b) risks rejecting a legitimately clock-skewed client, and (c) guards a marginal threat — the only writer is a signed-in UID writing its *own* `{oldUid}` doc; defeating TTL on one tiny pseudonymous doc per controlled UID requires App-Check-gated UID rotation and self-harms (their own cleanup). The presence+type guarantee already ensures legitimate intents are reaped. **Not worth the novel-syntax risk.** (Open for the Gate to overturn.)

### 3.3 TTL declaration (`firestore.indexes.json`)

Append to `fieldOverrides`, mirroring the existing three:
```json
{
  "collectionGroup": "recoveryCleanupIntents",
  "fieldPath": "expiresAt",
  "ttl": true,
  "indexes": [
    { "order": "ASCENDING", "queryScope": "COLLECTION" },
    { "order": "DESCENDING", "queryScope": "COLLECTION" },
    { "arrayConfig": "CONTAINS", "queryScope": "COLLECTION" }
  ]
}
```
This makes the TTL **reproducible from the tree** (issue checkbox 2). Actual production enablement happens via `firebase deploy --only firestore` at the unified backend deploy ceremony — the same ceremony that ships the not-yet-live rules (#192/#223 etc.). It is NOT a #170-specific lingering task; #170's deliverable is the declaration + rule + client field. (Do not flip the `PRODUCTION-READINESS.md` Firebase deploy blocker — pinned by `release_workflow_gate_test.dart`.)

### 3.4 Docs

`docs/SECURITY-RULES.md` §4.3b (and the table row ~:23) states "Exact key set `{secret, createdAt}`" — update to `{secret, createdAt, expiresAt}` + the `expiresAt > createdAt` constraint + a one-line TTL note. Same-PR (documents the exact change, not opportunistic).

## 4. Server — deliberately unchanged (Verification principle #6, decomposition of "validity")

`assertCleanupIntent` (`cleanupAnonUidArtifacts.ts:181-204`) keeps validity = `createdAt` age vs `cleanupIntentMaxAgeMs`. It must NOT start reading `expiresAt`: validity (15 min, security) and GC eligibility (24h, hygiene) are different invariants on purpose. Coupling them would either shorten validity to 24h or lengthen GC to 15 min (re-opening the early-reap-of-valid-intent risk). No server code change.

## 5. RED tests (write first, watch fail for the right reason)

1. **Rules (`firestore-rules-publish-readiness.test.ts`, the real RED).** Current rule `hasOnly(['secret','createdAt'])` rejects any write carrying `expiresAt`.
   - Update `validIntent` to include `expiresAt: new Date(Date.now() + 24*60*60*1000)`; assert the create + update **succeed** (RED today: extra key rejected → GREEN after rule change).
   - **Missing-`expiresAt` write fails** — `{secret, createdAt}` only → `assertFails` (RED today: it *succeeds*; GREEN after rule change makes `expiresAt is timestamp` mandatory). This is the load-bearing regression assertion.
   - **Past `expiresAt` fails** — `expiresAt = new Date(Date.now() - 1000)` → `assertFails` (exercises `expiresAt > createdAt`).
   - The existing extra-key (`newUid`) write must STILL fail (hasOnly admits `expiresAt`, not `newUid`).
   - The existing short-secret and wrong-UID failures must still fail.
2. **Dart (`test/.../auth_recovery_intent_payload_test.dart`, new).** Assert `AuthRecoveryService.buildCleanupIntentPayload('s'*40, clock: () => fixedNow)`:
   - keys are exactly `{secret, createdAt, expiresAt}`;
   - `secret` round-trips;
   - `createdAt` is a `FieldValue` (server sentinel);
   - `expiresAt` is a `Timestamp` equal to `fixedNow.toUtc() + 24h`.
   RED today: the method does not exist.

**Do NOT write** (Gate-pre-empt):
- No test asserting an *upper* bound on `expiresAt` (not in the design — see §3.2 rejected alternative). If the Gate adds the upper bound, add the test with it.
- No server-behavior test for `expiresAt` — the server ignores the field by design (§4); a server test would assert a non-contract.

## 6. Out of scope (do not bundle)
- Changing the 15-min server validity window or making the server read `expiresAt` (§4).
- TTL on `joinAttempts` (obs 24282 noted it lacks one) — separate collection, separate issue.
- Actual production TTL enablement / `firebase deploy` (deploy ceremony, not this PR).
- Backfilling `expiresAt` onto pre-existing intents (they expire by validity at 15 min and are dead; manual one-off cleanup if ever needed, not code).

## 7. Verification principles applied
- **#1 callsite classification:** §2 table — the OUTBOUND write is the only behavioral change; the INBOUND server read is deliberately untouched.
- **#2 claims vs code:** every path/line re-grepped this session (`cleanupIntentMaxAgeMs=15min` at :31; `hasOnly(['secret','createdAt'])` at :223; TTL absent from `firestore.indexes.json`; failure swallowed at :261-270).
- **#3 one read-path per write-path:** the sole reader of `expiresAt` is the TTL GC service; named explicitly.
- **#4 enumerate fields from the type:** intent doc fields enumerated from the rule + write site — `{secret, createdAt}` → `{secret, createdAt, expiresAt}`, exhaustive.
- **#5 spell out the contract:** exact key set, exact rule predicates, exact client value (`now+24h` as `Timestamp.fromDate`).
- **#6 decomposition:** "validity" ≠ "GC eligibility"; they are distinct invariants keyed on distinct fields (`createdAt` vs `expiresAt`), not the same number — §4.
- **#7 adversarial / orthogonal axis:** the fix is on the *write-shape* axis; the adversarial case is the **identity/abuse axis** — a signed-in client setting a hostile `expiresAt` (past → immediate self-reap = self-harm only; far-future → one persistent tiny doc, marginal) — analyzed in §3.2 to justify the lower-bound-only rule.
