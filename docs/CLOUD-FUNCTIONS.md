# Cloud Functions

Reference for the Firebase Cloud Functions Rihla ships: 14 HTTPS callables
(`firebase-functions/v2/https`), 12 Firestore document triggers
(`firebase-functions/v2/firestore`), and 5 scheduled backstops
(`firebase-functions/v2/scheduler`) — 31 functions total (count from
`tool/list_expected_functions.sh`, the deploy-drift SSOT), all deployed to
`us-central1`. The deploy-drift check reads the expected set from
`tool/list_expected_functions.sh` (add new functions as `export { … } from`
re-exports in `index.ts` or they escape it). `joinGroupByInviteCode` enforces
App Check; `deleteAccount` runs with App Check in verify-if-present (soft) mode.

| Callable | File | Purpose |
|----------|------|---------|
| `joinGroupByInviteCode` | `functions/src/callables/joinGroupByInviteCode.ts` | Validate a 6-char invite code and atomically add the caller to the group + active events. |
| `deleteAccount` | `functions/src/callables/deleteAccount.ts` | Server-side account-deletion cascade: revoke refresh tokens, scrub PII, replace UID with a per-group tombstone, delete FCM/joinAttempts/Auth user. On an incomplete cascade it writes a `deletionAudit/{uid}` marker (#76) for the reaper backstop. Creator succession picks the oldest real member via the shared `oldestRealMemberUid` (`shared/membership.ts`) — never a shadow/non-member (#1138). |
| `deleteGroup` | `functions/src/callables/deleteGroup.ts` | Server-authoritative group delete + cascade; gated on the caller being the **current-member** group creator (#1132) + a zero net balance via the shared `recomputeNet` oracle (#190). |
| `leaveGroup` | `functions/src/callables/leaveGroup.ts` | Member self-leave; gated on the leaver's net == 0 (shared oracle snapshot) UNDER a `departureInProgress` lock (#1144 — contention/lost lock → `aborted`); ALSO refuses (`failed-precondition`) while the leaver holds universe-only history — payer/settlement party in an event that no longer rosters them would fold in post-departure (#1144 R1, `universeOnlyEventIds`); hard-delete, not tombstone — leave doesn't touch `participantIds` (#290). A **creator** leave hands `createdBy` to the oldest real remaining member (never a shadow/non-member) and flips their member-doc `role`; no real survivor → the group is soft-deleted. Succession is a **permanent** handoff — rejoin does not restore authority (#1138). |
| `removeMember` | `functions/src/callables/removeMember.ts` | Current-member creator (#1132) removes another member; gates the TARGET's net == 0 (shared oracle snapshot) UNDER the #1144 departure lock + the same #1144 R1 universe-only refusal as `leaveGroup`; self-removal rejected (#318). |
| `addShadowMember` | `functions/src/callables/addShadowMember.ts` | Current-member creator (#1132) adds an unclaimed placeholder ("shadow") member by name (uuid-keyed; `doc.id===userId===randomUUID()`) — the only path that mints a member doc by name (#278). |
| `requestClaimShadow` | `functions/src/callables/requestClaimShadow.ts` | A joiner requests to claim an unclaimed shadow's identity + balance (#278). |
| `decideClaimRequest` | `functions/src/callables/decideClaimRequest.ts` | Current-member creator (#1132) approves/denies a claim; on approve runs the uuid→uid re-key engine `claimShadowEngine` (de-exported — reachable only via this callable) (#278). |
| `listMyClaimRequests` | `functions/src/callables/listMyClaimRequests.ts` | Lists the caller's pending/decided claim requests (#278). |
| `listGroupClaimRequests` | `functions/src/callables/listGroupClaimRequests.ts` | Current-member creator-side (#1132) list of pending claim requests for a group (#278). |
| `listUnclaimedShadows` | `functions/src/callables/listUnclaimedShadows.ts` | Lists a group's unclaimed shadows so a joiner can offer to claim one (#278). |
| `recordSettlement` | `functions/src/callables/recordSettlement.ts` | **The ONLY settlement create path (#1129)** — one transaction recomputes the pair's outstanding on the settle's scope basis via the shared oracle, rejects `amountFils > outstanding` (`{kind:'over-outstanding'}`), derives the #1093 `sd1` dedup id from the client's `observedPairEpoch` (retry → `alreadyRecorded`), and writes the settlement doc(s) + the ONE activity row atomically. Modes: `event` \| `group` \| `groupSettleUp` (≤400 legs; conservation + per-event leg caps server-verified). Online-only by nature. |
| `correctSettlement` | `functions/src/callables/correctSettlement.ts` | Server-authoritative solo correction (#889): writes the offsetting reverse row with the un-forgeable `correctionOfSettlementId` marker. |
| `correctLogicalSettleUp` | `functions/src/callables/correctLogicalSettleUp.ts` | Reverses every live doc sharing one `groupSettleUpId` atomically (#889/#753). |

Functions live in `functions/` (Node 22 / TypeScript). They use the
Firebase Admin SDK which **bypasses Firestore Security Rules** — every
authorization check is implemented inside the callable bodies.

**#1144 R5 — roster-writer contract:** every callable that mutates
`groups/{gid}.memberIds` (join, addShadowMember, leaveGroup, removeMember,
claimShadowEngine, deleteAccount) also maintains `activeMemberIds`
(= memberIds minus tombstone ids; shadows in) through the shared
`nextActiveMemberIds` helper (`callables/shared/activeMembers.ts`) inside
the same transaction — present field: apply the op; absent (legacy):
seed from memberIds − tombstone member docs, then apply. Never
FieldValue-array-op this field; always write the computed array. A new
roster writer MUST call the helper.

Top-level wiring:

```ts
// functions/src/index.ts
import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

export { joinGroupByInviteCode } from './callables/joinGroupByInviteCode';
export { deleteAccount } from './callables/deleteAccount';
export { deleteGroup } from './callables/deleteGroup';
export { leaveGroup } from './callables/leaveGroup';
export { removeMember } from './callables/removeMember';
export { addShadowMember } from './callables/addShadowMember';
export { requestClaimShadow } from './callables/requestClaimShadow';
export { decideClaimRequest } from './callables/decideClaimRequest';
export { listMyClaimRequests } from './callables/listMyClaimRequests';
export { listGroupClaimRequests } from './callables/listGroupClaimRequests';
export { listUnclaimedShadows } from './callables/listUnclaimedShadows';
export { recordSettlement } from './callables/recordSettlement';
export {
  eventWriteRateMonitor,
  groupActivityWriteRateMonitor,
} from './triggers/writeRateMonitor';
export {
  eventSettlementNotifier,
  groupSettlementNotifier,
} from './triggers/settlementNotifier';
export { expenseAuditLogger } from './triggers/expenseAuditLogger';
export { expenseNotifier } from './triggers/expenseNotifier';
export { eventNotifier } from './triggers/eventNotifier';
export { claimRequestNotifier } from './triggers/claimRequestNotifier';
export {
  eventModuleBalanceAggregator,
  groupSettlementBalanceAggregator,
  eventBalanceAggregator,
  memberBalanceAggregator,
} from './triggers/balanceAggregator';
export { deletionReaper } from './scheduled/deletionReaper';
export { balanceReconciler } from './scheduled/balanceReconciler';
export { deleteGroupLockReaper } from './scheduled/deleteGroupLockReaper';
```

The Flutter client wraps the callables in
`lib/core/services/firebase_functions_service.dart`. The join callable
has its own service inside the `groups` feature. The triggers and the
scheduled reaper have no client surface — they fire server-side.

## Scheduled functions

There are **5** `onSchedule` jobs: `deletionReaper` (below), `balanceReconciler`
(`scheduled/balanceReconciler.ts` — periodically recomputes the
`groups/{gid}/aggregates/balance` display cache, #366), `deleteGroupLockReaper`
(`scheduled/deleteGroupLockReaper.ts` — resumes a `deleteGroup` cascade stalled
past its lock horizon, #519/#529), `claimShadowLockReaper`
(`scheduled/claimShadowLockReaper.ts` — resumes a claim re-key stalled past its
lock horizon), and `departureLockReaper` (`scheduled/departureLockReaper.ts` —
clears a `departureInProgress` lock lingering after a killed
`leaveGroup`/`removeMember`; nothing to resume — the membership mutation
releases the lock atomically, so a lingering lock proves it never committed,
#1144).

### Deletion reaper (#76)

`functions/src/scheduled/deletionReaper.ts` is an `onSchedule` job (runs
`every 24 hours`). It is the server-side backstop for the
"user uninstalls / never retries" tail of `deleteAccount`:

- When a `deleteAccount` cascade is incomplete (partial scrub, or the Auth
  delete failed), the **shared core** `runAccountDeletionCascade` (exported
  from `deleteAccount.ts`, called by both the callable and the reaper) writes
  a server-only `deletionAudit/{uid}` marker (`status:'failed'`,
  `firstFailedAt`/`lastAttemptAt`/`attemptCount`, TTL `expiresAt`).
- The reaper queries markers whose `lastAttemptAt` is older than the grace
  window (`DELETION_REAPER_GRACE_MS`, default 24h — so a client still
  retrying is never double-processed), up to `DELETION_REAPER_BATCH` (default
  50) per run, and re-runs the idempotent, convergent (#46) cascade for each.
- On convergence the core **deletes** the marker (including the self-heal
  case where the Auth user is already gone — `auth/user-not-found` is treated
  as complete, never stranded); on a re-failure it refreshes the marker.

**Token revocation:** the core calls `getAuth().revokeRefreshTokens(uid)`
before the scrub. This bounds the post-partial-failure replay window to one
ID-token lifetime (≤1h) — it stops the preserved user from minting a new ID
token. It does **not** retroactively invalidate an outstanding ID token
(Firestore rules and callables do not check revocation); the reaper's eventual
`deleteUser` is the full closure.

## Firestore triggers — write-rate monitor (#198)

`functions/src/triggers/writeRateMonitor.ts` ships two `onDocumentCreated`
triggers that share one handler. They are **detection-only**: expense /
activity creates are client-direct (Firestore offline replay — a trigger
fires *after* commit and cannot reject), so the monitor only **flags**
per-UID write bursts; it never deletes or mutates the financial doc.
Settlement creates are NOT counted since #1129 — they are callable-routed
(`recordSettlement`, unforgeable via rules), and a large decomposed
settle-up would otherwise false-flag the threshold; the old
`groupSettlementWriteRateMonitor` trigger was deleted with the flip. App
Check is irrelevant here (triggers are server-internal, not called by
clients).

| Trigger | Document path | Covers |
|---------|---------------|--------|
| `eventWriteRateMonitor` | `groups/{gid}/events/{eid}/{module}/{docId}` | event `expenses` only (wildcard `{module}`, filtered) |
| `groupActivityWriteRateMonitor` | `groups/{gid}/activity/{activityId}` | group-level activity (server-authored types incl. both settlement flavors are skip-listed) |

Each create increments `groups/{gid}/_writeCounters/{uid}` (server-only,
TTL on `expiresAt`) in a transaction. Actor = `createdBy` (expenses/
settlements) or `actorId` (activity). On the first write that exceeds
`WRITE_RATE_LIMIT` (default 100/min; `process.env.WRITE_RATE_LIMIT` seam)
within the 60s window it logs a single `write-rate burst flagged` warning
and stamps `lastFlaggedAt`. None of the trigger paths match
`_writeCounters`, so the counter write never re-fires a trigger.
Response to a flag is **manual** (ops sees the log, then intervenes).

## Firestore triggers — push notifications (#53)

`functions/src/triggers/settlementNotifier.ts` ships two `onDocumentCreated`
triggers that send **push notifications** when a settlement is recorded. Like
the write-rate monitor they fire *after* commit and only read + send — they
never mutate the financial doc. They give the previously-orphaned
`fcm_tokens/{uid}` PII a real purpose (resolves the #53 data-minimization
concern by building the sender, not by removing the tokens).

| Trigger | Document path | Notifies |
|---------|---------------|----------|
| `eventSettlementNotifier` | `groups/{gid}/events/{eid}/settlements/{id}` | the counterparty (settlement parties **minus** `createdBy`) |
| `groupSettlementNotifier` | `groups/{gid}/settlements/{id}` | same, for group-level settlements |

Member-join pushes are **not** a trigger — they fire as a fire-and-forget
side-effect inside `joinGroupByInviteCode` after a committed BRAND-NEW join
(gated so an idempotent/heal re-join never re-announces; a notify failure
never fails the join).

Shared sender infrastructure under `functions/src/notifications/`:

- `fcmSender.ts` — `sendToUids(uids, build, data)`: reads `fcm_tokens/{uid}`,
  sends one **per-recipient-locale** `Message` via `getMessaging().sendEach`,
  prunes not-registered/invalid tokens, and **never throws**. uids that have
  no token doc (shadow/unclaimed members, opted-out users) are skipped.
- `strings.ts` — bilingual (en/ar) copy + `normalizeLocale`. The recipient
  locale is read from `fcm_tokens/{uid}.locale` (written by the client), so
  copy renders correctly even when the app is terminated and the OS draws the
  notification.
- `formatAmount.ts` — display-only money formatter mirroring `MoneySerializer`'s
  currency scale (case-insensitive; OMR fallback). Table-tested.

The `data` payload (`{type, groupId, eventId?}`, all string values) drives the
client tap route to `/group/:gid`. Client consumer: `lib/core/services/
notification_service.dart` (+ `local_notifier.dart`). **iOS push is inert**
until APNs cert + entitlement are configured (no iOS CI) — tracked as a
follow-up; the client stays crash-safe and the token is still stored.

## Firestore triggers — audit log & balance aggregation

Beyond the write-rate monitor (#198) and settlement notifiers (#53), these
triggers fire server-side after commit:

| Trigger | Type / path | Purpose |
|---------|-------------|---------|
| `expenseAuditLogger` | `onDocumentWritten` `groups/{gid}/events/{eid}/expenses/{expenseId}` | Server-authored, tamper-proof audit of every expense create/edit/soft-delete; attributes the actor from the rules-pinned `lastEditedBy` (B1 / #248). |
| `expenseNotifier` | `onDocumentCreated` `groups/{gid}/events/{eid}/expenses/{expenseId}` | Push to event participants on a new expense (#179). |
| `eventNotifier` | `onDocumentCreated` `groups/{gid}/events/{eid}` | Push to group members on a new event (#179). |
| `claimRequestNotifier` | `onDocumentWritten` `groups/{gid}/claimRequests/{requestId}` | Push to the group creator when a claim request arrives (re-open-safe status guard) (#560). |
| `eventModuleBalanceAggregator` | `onDocumentWritten` `groups/{gid}/events/{eid}/{module}/{docId}` | Maintains the per-currency `groups/{gid}/aggregates/balance` display cache via `recomputeNet` (#366/#382). |
| `eventBalanceAggregator` | `onDocumentWritten` `groups/{gid}/events/{eid}` | Same cache, on event-doc changes. |
| `groupSettlementBalanceAggregator` | `onDocumentWritten` `groups/{gid}/settlements/{settlementId}` | Same cache, on group-settlement changes. |
| `memberBalanceAggregator` | `onDocumentWritten` `groups/{gid}/members/{memberId}` | Same cache, on membership changes. |

The 4 `balanceAggregator` triggers reuse the same `recomputeNet` oracle as
`deleteGroup`/`leaveGroup`/`removeMember`; the aggregate doc is a **display
cache, never OUTBOUND** (see CLAUDE.md money landmines).

---

## 1. `joinGroupByInviteCode`

Server-side join flow. The client cannot read `inviteCodes/*` or write
to `groups/*/members/*` for a group it isn't already in — this callable
is the only path to membership.

### Signature

```ts
interface JoinGroupByInviteCodeInput {
  inviteCode: string;
  displayName?: string;
}

interface JoinGroupByInviteCodeOutput {
  groupId: string;
}
```

### Behaviour

1. **Auth gate.** Throws `unauthenticated` if `request.auth` is null.
2. **Invite-code normalization.** Trims, uppercases, and matches
   `^[A-Z0-9]{6}$`. Anything else → `invalid-argument` `"Invalid invite code."`.
3. **Display-name normalization.** Optional; defaults to `"Anonymous"`.
   When provided, must be 1-32 chars and free of control characters
   (`\x00-\x1F\x7F`). Validation matches the Firestore rule
   `isValidDisplayName` in `security/firestore.rules`.
4. **Rate-limit gate.** Checks `joinAttempts/{uid}.lockedUntil`. If a
   lock is active, throws `resource-exhausted` `"Too many attempts. Try again later."`
5. **Atomic transaction.** Reads `inviteCodes/{code}`, the target
   group, the caller's member doc, and the events subcollection. A join
   targeting a soft-deleted group (`isDeleted === true`) is rejected with
   `not-found` `"Group not found."` (#78) and counts as a lookup failure
   toward the rate limit, mirroring an invalid code. If the group exists
   and the caller isn't yet a member, writes:
   - `groups/{gid}.memberIds` += `uid` (arrayUnion)
   - `groups/{gid}/members/{uid}` = full member doc
   - For each non-deleted event: add `uid` to `participantIds` and set
     `participantNames[uid] = displayName` (a.k.a. event fan-out)
6. **Failure rate-limit.** If the invite code is not found, increments
   the failure counter at `joinAttempts/{uid}`. After 5 failures in a
   rolling 60-minute window, sets a 60-minute lock and surfaces
   `resource-exhausted`.
7. **Success cleanup.** Deletes `joinAttempts/{uid}` and logs
   `"group-join succeeded"`.

### Constants

| Name | Value | Purpose |
|------|-------|---------|
| `JOIN_ATTEMPT_WINDOW_MS` | 3,600,000 (1h) | Window over which failed attempts accumulate. |
| `JOIN_ATTEMPT_LOCK_MS` | 3,600,000 (1h) | Duration of the cool-down after the 5th failure. |
| `JOIN_ATTEMPT_LIMIT` | 5 | Failures before lockout. |
| `DISPLAY_NAME_MAX_LENGTH` | 32 | Server-side validation cap, matches Firestore rule. |
| Per-group event cap | 400 | A group with more than 400 events fails `failed-precondition` to keep the transaction within Firestore's 500-write budget. |

### Errors

| Code | Message | When |
|------|---------|------|
| `unauthenticated` | Sign-in required. | No `request.auth`. |
| `invalid-argument` | inviteCode must be a string. | Wrong type. |
| `invalid-argument` | Invalid invite code. | Fails the `^[A-Z0-9]{6}$` regex. |
| `invalid-argument` | displayName must be a string. | Wrong type when provided. |
| `invalid-argument` | displayName must be between 1 and 32 characters. | Length out of bounds. |
| `invalid-argument` | displayName contains invalid characters. | Contains a control character. |
| `not-found` | Invalid invite code. | Code regex matches but no `inviteCodes/*` doc exists. Counts toward the rate-limit. |
| `not-found` | Group not found. | Invite doc points to a missing group, or the target group is soft-deleted (`isDeleted === true`, #78). Counts toward the rate-limit. |
| `failed-precondition` | Invite code is malformed. | `inviteCodes/{code}.groupId` not a string. |
| `failed-precondition` | Group membership data is malformed. | `memberIds` not an array of strings. |
| `failed-precondition` | Event `{id}` participantIds data is malformed. | Event participantIds malformed. |
| `failed-precondition` | Event `{id}` participantNames data is malformed. | Event participantNames malformed. |
| `failed-precondition` | Group has too many events to join safely. | >400 events. |
| `resource-exhausted` | Too many attempts. Try again later. | Lock active or 5th failure. |

### Client wrapper

```dart
// lib/features/groups/services/group_service.dart (or equivalent)
final res = await FirebaseFunctions.instance
  .httpsCallable('joinGroupByInviteCode')
  .call({'inviteCode': code, 'displayName': name});
final groupId = res.data['groupId'] as String;
```

Errors come back as `FirebaseFunctionsException` with `.code` carrying
the codes above (mapped to enum values like `not-found`,
`resource-exhausted`, etc.). The Join screen maps each to a friendly
user-facing string.

### Operational notes

Runbook entries T2 and T3 (`docs/RUNBOOK.md`) cover error-rate
tripwires for this callable. The 5/hr lockout is intentional — a
shared invite code going viral will trigger throttling, which is the
expected behaviour, not a bug.

---

## 3. `deleteAccount`

In-app account deletion. Cascades through Firestore, FCM tokens,
joinAttempts, and finally the Firebase Auth user.

### Signature

```ts
type DeleteAccountInput = void;  // accepts no input

interface DeleteAccountOutput {
  groupsProcessed: number;
  tombstoneIds: string[];
  expensesScrubbed: number;
  settlementsScrubbed: number;
  activityLogsScrubbed: number;
  membersDeleted: number;
  groupsOrphanedAndSoftDeleted: number;
  // group ids (or the sentinels 'fcm_tokens' / 'joinAttempts') whose
  // scrub failed. While non-empty, the Auth user is preserved and the
  // callable throws.
  cascadeFailed: string[];
  fcmTokenDeleted: boolean;
  joinAttemptsDeleted: boolean;
  authUserDeleted: boolean;
}
```

### Behaviour

1. **Auth gate.** Throws `unauthenticated` if `request.auth` is null.
2. **Rate-limit gate.** `enforceDeletionRateLimit` throws
   `resource-exhausted` `"Too many deletion attempts. Try again later."`
   if the UID has invoked deletion more than 5 times in a rolling
   60-minute window (#73). Runs **before** the input gate so malformed
   and replayed calls are both counted.
3. **Input gate.** Accepts only `null` or `{}`. Anything else →
   `invalid-argument`.
4. **Per-group cascade.** For each group where `memberIds` contains
   the caller's UID:
   - Derive a deterministic tombstone ID `deleted-<sha1(uid)[:8]>`
     (deterministic so a retried cascade reuses the same identity;
     collisions get a `-2`, `-3`… suffix).
   - Create `groups/{gid}/members/{tombstoneId}` with
     `displayName: "Deleted member"`, `role: 'MEMBER'`,
     `isTombstone: true`. Preserves `joinedAt` from the old member doc.
   - Delete every `groups/{gid}/members/{memberDocId}` whose `userId == uid`.
   - Rewrite `groups/{gid}.memberIds`: caller's UID → tombstoneId.
   - If `createdBy == uid` and another real member exists, transfer
     creator to the oldest remaining real member. If no other real
     member exists, set `createdBy = 'deleted-user'` and soft-delete
     the group (`isDeleted: true`, `deletedAt: serverTimestamp`).
   - For each event in the group: rewrite `participantIds`,
     `participantNames`, and `createdBy` analogously; re-key `closedBy`
     → tombstoneId; and scrub the frozen `spendingSnapshot` (re-key
     `biggest.payer` / `payers[].id` / `owed` keys → tombstoneId with a
     SUM-on-collision merge for the uid-keyed `owed` money map, and drop
     every frozen `biggest.desc`) — but only when the snapshot references
     the uid (#1133). The cascade only reaches groups the uid is still a
     member of at deletion time (`memberIds array-contains uid`).
   - For each expense: rewrite `createdBy`, `payerParticipantId`,
     `customSplitParticipants`, and `splitDistribution` keys. **Null
     out** `receiptUrl`, `note`, and `description` to scrub PII.
   - For each settlement: rewrite participant references and null out
     `note`.
   - For each activity log: rewrite `actorId`/`actorName`, rewrite
     metadata, and replace the descriptive text with
     `"Deleted member activity"`.
5. **Top-level cleanup.** Deletes `fcm_tokens/{uid}` and
   `joinAttempts/{uid}` if they exist.
6. **Partial-failure gate.** If any group/fcm/joinAttempts scrub failed,
   their identifiers land in `cascadeFailed`. While `cascadeFailed` is
   non-empty the callable **preserves the Auth user** and throws
   `internal` `"Account deletion did not finish; please try again."`
   with the partial output in `details` — it does **not** return a
   partial success. The session stays valid so the client can retry the
   idempotent cascade.
7. **Auth user deletion.** Only when `cascadeFailed` is empty, calls
   `getAuth().deleteUser(uid)`. If the user is already gone
   (`auth/user-not-found`), `output.authUserDeleted = false`. Any other
   failure throws `internal` with the cleanup output attached.
8. **Returns** a tally of everything scrubbed for client display +
   audit logging.

### Why a tombstone instead of hard delete?

Money math depends on `participantIds` and `payerParticipantId`
remaining stable. Hard-deleting a member would orphan every expense
and settlement they touched. The tombstone preserves the audit trail
and keeps `BalanceCalculator` working for the survivors. The deleted
user's identity is replaced with the sentinel name `"Deleted member"`
and a non-PII tombstone ID.

### `BatchWriter`

The callable funnels all writes through an internal `BatchWriter` that
auto-flushes every 450 operations to stay under Firestore's 500-write
batch limit. Large cascades therefore commit in chunks — partial
failure is possible if the function times out mid-cascade, but each
chunk is internally consistent.

### Errors

| Code | Message | When |
|------|---------|------|
| `unauthenticated` | Sign-in required. | No `request.auth`. |
| `resource-exhausted` | Too many deletion attempts. Try again later. | More than 5 deletion invocations per UID in a rolling 60-minute window (#73). Thrown before any cascade. |
| `invalid-argument` | deleteAccount does not accept input. | Non-empty/non-null `request.data`. |
| `failed-precondition` | `<path>` is malformed. | `memberIds` schema violation in a group doc. |
| `not-found` | Group `{id}` no longer exists. | A group disappeared mid-cascade. |
| `internal` | Account deletion did not finish; please try again. | One or more group/fcm/joinAttempts scrubs failed; Auth user preserved, partial output in `details`, client must retry. |
| `internal` | Account data was scrubbed, but the Auth user could not be deleted. | Auth deletion failed for a non-`user-not-found` reason. `details` payload carries the partial output. |

### Client wrapper

```dart
// lib/core/services/firebase_functions_service.dart
Future<void> deleteAccount() async {
  await _functions.httpsCallable('deleteAccount').call(<String, dynamic>{});
}
```

Triggered from Profile → Account → Delete account, after a confirmation
dialog (`DeleteAccountDialog`). On success the client signs out and
routes to the post-deletion empty state.

---

## App Check

`joinGroupByInviteCode` ships with
`{ enforceAppCheck: true }`. The client must hold a valid App Check
token (Play Integrity on Android, App Attest / DeviceCheck on iOS) or
the callable returns `unauthenticated` before any logic runs.
`deleteAccount` ships with `{ enforceAppCheck: false }` (#73) so a
self-scoped account deletion still works on devices that fail Play
Integrity / App Attest; a per-UID deletion rate limit (5/hr) is the
compensating control.

Debug builds and the emulator suite bypass enforcement when
`FirebaseConfig.initialize(useDebugAppCheck: true)` is called — see
`lib/main.dart:56`. The release pipeline gates on the
`RIHLA_APP_CHECK_READY` repo variable and the commit-bound
`RIHLA_RELEASE_APPROVED_SHA` variable to prevent shipping a build that
would 100% fail App Check or reusing stale release approvals on a newer
commit.

---

## Local development

### Run against the emulator

```bash
# Terminal 1 — start the suite
cd functions && firebase emulators:start --only auth,firestore,functions

# Terminal 2 — point the app at the emulator
flutter run --dart-define-from-file=config.json
# (config.json must contain "USE_FIREBASE_EMULATOR": true)
```

The emulator suite binds Functions to port 5001. The Flutter side
(`lib/main.dart:62-71`) auto-detects Android emulators (uses
`10.0.2.2`) vs. iOS simulators / desktop (uses `localhost`).

### Run callable tests

```bash
cd functions
npm test
```

Tests use the Firestore emulator under Java 21. See
`functions/package.json` and `functions/jest.config.js`.

### Deploy

Functions deploy via the same script the readiness check uses:

```bash
RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA="$(git rev-parse HEAD)" bash tool/deploy_firebase_backend.sh rihla-safar
```

The script refuses to deploy unless both env gates are present, the approved SHA
matches the current commit, and the App Check repo variables agree.

---

## Files at a glance

| File | Lines | Notes |
|------|-------|-------|
| `functions/src/index.ts` | 42 | Region + 31 re-exports (13 callables, 13 triggers, 5 scheduled) |
| `functions/src/admin.ts` | 5 | `initializeApp()` side-effect |
| `functions/src/callables/joinGroupByInviteCode.ts` | 327 | Invite-code redemption + event fan-out |
| `functions/src/callables/deleteAccount.ts` | 746 | Account deletion cascade + tombstones |
| `functions/src/triggers/settlementNotifier.ts` | — | #53 settlement-recorded push triggers |
| `functions/src/notifications/fcmSender.ts` | — | #53 multicast sender + token pruning |
| `functions/src/notifications/strings.ts` | — | #53 bilingual push copy + `normalizeLocale` |
| `functions/src/notifications/formatAmount.ts` | — | #53 display money formatter (mirrors MoneySerializer) |
| `functions/src/notifications/memberJoinNotifier.ts` | — | #53 member-join push helper |
| `functions/package.json` | — | Node 22 / TypeScript / Jest |
| `functions/jest.config.js` | — | Test config |
| `lib/core/services/firebase_functions_service.dart` | 24 | Flutter client wrapper |
| `security/firestore.rules` | 755 | Companion rules; see [SECURITY-RULES.md](./SECURITY-RULES.md) |

---

## Related docs

- [SECURITY-RULES.md](./SECURITY-RULES.md) — what's enforced at the rules layer
- [ACCOUNT-RECOVERY.md](./ACCOUNT-RECOVERY.md) — the durable-credential recovery architecture
- [RUNBOOK.md](./RUNBOOK.md) — tripwires T2 and T3 cover Cloud Functions error rates
- [PRODUCTION-READINESS.md](./PRODUCTION-READINESS.md) — pre-deploy checklist
- [ARCHITECTURE.md](./ARCHITECTURE.md) — overall system picture
