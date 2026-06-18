# #560 — Notify the group creator when a claim request arrives

**Date:** 2026-06-18
**Issue:** #560 (P2, #278 PR9 follow-up P9-1)
**Category:** Cloud Functions (Gate-category — runs the Gate; deploy surface).

## Problem

After #278, a real person can request to claim a placeholder ("shadow") member
before joining (`requestClaimShadow` → writes a `groups/{gid}/claimRequests/{id}`
doc, `status: 'pending'`). The group creator approves via `decideClaimRequest`.
Today the creator only discovers a pending request by **opening Group Settings**
(poll-on-open of `listGroupClaimRequests`). The requester sits on a "Waiting for
approval" screen until the creator happens to look.

**Ask:** an FCM trigger on a claim-request arrival that pushes the creator
"{requester} wants to claim {shadow}'s spot", mirroring `settlementNotifier` /
`eventNotifier`. Discoverability gap, not a correctness bug — the flow works.

## Scope (backend-only)

| File | Change |
|---|---|
| `functions/src/triggers/claimRequestNotifier.ts` | **new** trigger |
| `functions/src/notifications/strings.ts` | add `claimRequestTitle` + `claimRequestBody` (en/ar) |
| `functions/src/index.ts` | re-export `claimRequestNotifier` (deploy-drift extractor reads this) |
| `functions/test/triggers/claimRequestNotifier.test.ts` | **new** RED-first trigger test |
| `functions/test/notifications/strings.test.ts` | add copy assertions |

**No client change.** The notification `data` payload carries routing info but
the client ignores tap-routing in v1 (same as expense/event/settlement pushes —
obs 28814). Tapping opens the app; the creator opens Group Settings to approve.
Deep-link-to-approve is a v2 follow-up, out of scope.

## Design

### Trigger type: `onDocumentWritten`, NOT `onDocumentCreated`

This is the one real decision. The sibling notifiers (`settlementNotifier`,
`eventNotifier`) use `onDocumentCreated` because their docs are **append-only** —
a settlement/event is created once and never re-`set`. `claimRequests` is
**mutable**:

`requestClaimShadow` writes with a **deterministic id** `${uid}__${shadowMemberId}`
via `.set()` (requestClaimShadow.ts:112-130). So:
- First request → doc **created** (`onDocumentCreated` would fire).
- Re-request after a creator **decline** → `.set()` on the existing doc =
  **update** `declined → pending` (`onDocumentCreated` would **NOT** fire → the
  creator never learns of the retry — defeats the issue's goal).

So `onDocumentCreated` under-covers. Use `onDocumentWritten` with a transition
guard that fires exactly on "a request just became pending":

```
const before = change?.before.exists ? change.before.data() : undefined;
const after  = change?.after.exists  ? change.after.data()  : undefined;
if (after?.status !== 'pending') return;          // only act on arrivals at pending
if (before?.status === 'pending') return;         // skip no-op re-writes of an already-pending doc
```

### Re-fire safety — every writer to `claimRequests` enumerated

The collection is new in #278 PR8. The **only** writers (grep `claimRequests`
across `functions/src`, excluding the read-only `listGroup/MyClaimRequests`):

| Writer | Op | before.status → after.status | Guard verdict |
|---|---|---|---|
| `requestClaimShadow` | `.set()` create | ∅ → `pending` | **NOTIFY** ✓ (the arrival) |
| `requestClaimShadow` | `.set()` re-open | `declined` → `pending` | **NOTIFY** ✓ (the retry) |
| `requestClaimShadow` | `.set()` no-op | `pending` → `pending` | skip (before is pending) ✓ |
| `decideClaimRequest` | `.update()` approve | `pending` → `claimed` | skip (after ≠ pending) ✓ |
| `decideClaimRequest` | `.update()` decline | `pending` → `declined` | skip (after ≠ pending) ✓ |
| `decideClaimRequest` | `.update()` already-claimed decline (decideClaimRequest.ts:134-139) | `pending` → `declined` | skip (after ≠ pending) ✓ |
| _(future delete cascade)_ | `.delete()` | `pending` → ∅ | skip (after undefined) ✓ |

`claimed → pending` re-open is **impossible** — `requestClaimShadow.ts:114-117`
throws if the existing doc is already `claimed`, *before* the `.set()`. So the
guard never sees a reopened-claimed transition.

No `deleteGroup` / `deleteAccount` / `cleanupAnonUidArtifacts` path references
`claimRequests` (verified by grep). The guard is provably correct for the full
writer set.

### Target = the group creator (single uid)

The recipient is `group.createdBy` — an **auth uid** (it is the creator trust
anchor: `decideClaimRequest.ts:67` `groupData.createdBy !== uid`). It maps
directly to `fcm_tokens/{uid}`. Read it from the **group doc**, not the request
doc (the request doc has no creator field).

Defensive filter `requesterUid !== createdBy`: a creator can never be the
requester (`requestClaimShadow` rejects existing members; the creator is always a
member) — but mirror the `uid !== createdBy` self-skip the other notifiers use.

An **anonymous** creator may have no `fcm_tokens/{uid}` doc → `sendToUids` skips
silently. Best-effort, acceptable for P2.

### Copy (`strings.ts`, bilingual)

- **Title:** `groupLabel(locale, groupName)` — identical convention to every
  other notifier title (settlement/event/expense/memberJoin all = `groupLabel`).
- **Body:** `claimRequestBody(locale, requesterName, shadowName)`
  - requester empty → `actorLabel` fallback (`Someone` / `شخص ما`) — #483 pattern.
  - shadow empty → a localized "a member" fallback (avoids a dangling possessive).
  - EN: `${requester} wants to claim ${shadow}'s spot.`
  - AR: `يريد ${requester} أخذ مكان ${shadow}.`

Both names are stored on the doc with non-empty defaults by `requestClaimShadow`
(`Anonymous` / `Member`), so the empty branches only guard legacy/malformed docs.

### Payload

`{ type: 'claim_request', groupId: gid }` — all string values (FCM requirement).
No `eventId` (claims are group-scoped). `type` is new; client ignores it in v1.

## Data contract (claimRequests doc — enumerated from requestClaimShadow.ts:121-130)

`requesterUid`, `requesterDisplayName`, `shadowMemberId`, `shadowDisplayName`,
`status`, `createdAt`, `decidedBy`, `decidedAt`. The trigger **reads** `status`
(guard), `requesterUid` (self-skip), `requesterDisplayName`, `shadowDisplayName`.
It **writes nothing** to any domain doc (read-only notifier; `sendToUids` may
prune a dead `fcm_tokens` row only).

## Verification principles (run inline)

1. **Callsite classification:** trigger is **INBOUND/read-only**. No OUTBOUND
   path; it never persists a display string. ✓
2. **Concrete claims vs code:** doc fields ← requestClaimShadow.ts:121-130;
   `createdBy` auth-uid ← decideClaimRequest.ts:67; `sendToUids` sig ←
   fcmSender.ts:43; `onDocumentWritten` before/after ← expenseAuditLogger.ts:151-153;
   index re-export ← index.ts:27-28. All re-grepped this session. ✓
3. **One read-path per write-path:** no write-path. The reacted-to write is
   `requestClaimShadow.set()`; the "read" is the creator's device rendering the push. ✓
4. **Fields from the type:** enumerated above (8 fields); uses 4, writes 0. ✓
5. **Data contracts spelled out:** trigger path, guard predicate, target list,
   copy signatures, payload keys — all literal above. ✓
6. **Arithmetic decomposition:** N/A — no money math. ✓
7. **Adversarial / orthogonal axes:** re-fire (full writer table), anon-creator
   (silent skip), empty-name (localized fallback), self-claim (defensive skip). ✓

## TDD plan (RED → GREEN)

`claimRequestNotifier.test.ts` (mirror settlementNotifier.test.ts harness:
`functionsTest`, `makeChange`, mocked `getMessaging().sendEach`, seeded
`fcm_tokens` + `groups`):

1. **create pending → creator notified** (seed group `createdBy=C`, token for C;
   fire `makeChange(∅, {status:'pending', requesterUid:'R', requesterDisplayName:'Sam', shadowDisplayName:'Dad'})`;
   assert `sendEach` called once, message token = C's, body contains `Sam`+`Dad`).
2. **declined → pending (re-open) → notified** (`makeChange({status:'declined',...}, {status:'pending',...})`).
3. **pending → claimed → NO send** (decide-approve).
4. **pending → declined → NO send** (decide-decline).
5. **pending → pending no-op → NO send**.
6. **delete (after ∅) → NO send**.
7. **creator has no token → no throw, no send** (anon creator).
8. **requester == creator (defensive) → NO send**.

`strings.test.ts`: `claimRequestBody` en + ar with both names; empty-requester
fallback; empty-shadow fallback. `claimRequestTitle` = group name + empty→fallback.

## Ship sequence

1. RED tests (1-8 + strings) → run scoped (`RIHLA_FIREBASE_EMULATOR_TEST_COMMAND=...
   claimRequestNotifier`) → confirm fail for the right reason.
2. Implement trigger + strings + index re-export → GREEN.
3. `npm run lint` + full emulator suite green.
4. Branch + commit (`feat(functions): notify creator on claim request arrival (#560)`),
   `Closes #560` in commit body.
5. /automerge (Gate-category → fresh review + refuter).
6. After merge: deploy ceremony (`pending_deploy.sh` → deploy → prod-state →
   advance `backend-deployed` tag → DEPLOY-LEDGER). New fn count 26 → 27.

## Out of scope / follow-ups

- Deep-link tap → approve screen (v2 routing; client ignores `type` in v1).
- Notifying the **requester** when the creator decides (approve/decline) — the
  requester already polls `listMyClaimRequests` on the waiting screen. Separate ask.
