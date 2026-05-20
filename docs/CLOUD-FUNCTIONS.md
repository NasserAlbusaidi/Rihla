# Cloud Functions

Reference for the three Firebase Cloud Functions Rihla ships. All three
are HTTPS callables under the v2 API (`firebase-functions/v2/https`),
deployed to `us-central1`, and enforce App Check.

| Callable | File | Purpose |
|----------|------|---------|
| `joinGroupByInviteCode` | `functions/src/callables/joinGroupByInviteCode.ts` | Validate a 6-char invite code and atomically add the caller to the group + active events. |
| `cleanupAnonUidArtifacts` | `functions/src/callables/cleanupAnonUidArtifacts.ts` | After email-link recovery, migrate Firestore + Auth references from the old anonymous UID to the recovered UID. |
| `deleteAccount` | `functions/src/callables/deleteAccount.ts` | Server-side account-deletion cascade: scrub PII, replace UID with a per-group tombstone, delete FCM/joinAttempts/Auth user. |

Functions live in `functions/` (Node 20 / TypeScript). They use the
Firebase Admin SDK which **bypasses Firestore Security Rules** — every
authorization check is implemented inside the callable bodies.

Top-level wiring:

```ts
// functions/src/index.ts
import { setGlobalOptions } from 'firebase-functions/v2';
import './admin';

setGlobalOptions({ region: 'us-central1' });

export { joinGroupByInviteCode } from './callables/joinGroupByInviteCode';
export { cleanupAnonUidArtifacts } from './callables/cleanupAnonUidArtifacts';
export { deleteAccount } from './callables/deleteAccount';
```

The Flutter client wraps the latter two in
`lib/core/services/firebase_functions_service.dart`. The join callable
has its own service inside the `groups` feature.

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
   group, the caller's member doc, and the events subcollection. If
   the group exists and the caller isn't yet a member, writes:
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
| `not-found` | Group not found. | Invite doc points to a missing group. |
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

## 2. `cleanupAnonUidArtifacts`

After a user links and recovers their account via email link, the
Firebase Auth UID changes from the anonymous `oldUid` to the recovered
`newUid`. Firestore documents that referenced `oldUid` (as a member,
participant, or creator) need to be rewritten — without this, the user
appears as two separate people in their own groups.

This callable does the rewrite server-side because the necessary cross-
document writes exceed what a client batch can do safely under the
security rules.

### Signature

```ts
interface CleanupAnonUidArtifactsInput {
  oldUid: string;
  cleanupSecret: string;
}

interface CleanupAnonUidArtifactsOutput {
  groupsProcessed: number;
  groupsFailed: string[];
  authUserDeleted: boolean;
  fcmTokenDeleted: boolean;
  joinAttemptsDeleted: boolean;
}
```

### Behaviour

1. **Auth gate.** Throws `unauthenticated` if `request.auth` is null.
2. **Input validation.** `oldUid` must be a non-empty string and must
   differ from the caller's current UID. `cleanupSecret` must be a
   32-128 character one-time secret.
3. **Cleanup intent precondition.** Before sign-out, the retiring
   anonymous UID writes `recoveryCleanupIntents/{oldUid}` with the
   secret. The callable verifies that document exists, matches the
   supplied secret, and is no older than 15 minutes. Without this, any
   recovered user who can see another anon UID could try to migrate that
   user's artifacts.
4. **Recovery precondition.** Calls `getAuth().getUser(newUid)` and
   verifies the user is linked to either `'password'` or `'emailLink'`
   provider. A pure-anon UID may not call this — there is nothing to
   recover into. `failed-precondition` if missing.
5. **Per-group cleanup transaction.** For every group where
   `memberIds` contains `oldUid`:
   - Rewrite `memberIds`: `[..., oldUid, ...]` → `[..., newUid, ...]`
     (dedupes if `newUid` already present).
   - If `createdBy == oldUid`, set `createdBy = newUid`.
   - If a member doc exists at `members/{oldUid}` and not at
     `members/{newUid}`, copy it over with `userId`/`id` rewritten.
   - Delete the old `members/{oldUid}` doc.
   - For each event in the group: rewrite `participantIds`,
     `participantNames` keys, and `createdBy` analogously. Same for
     each non-deleted expense's `createdBy`.
6. **Auth + keyed-artifact cleanup.** Deletes the Auth user for
   `oldUid` (ignores `auth/user-not-found`). Deletes
   `fcm_tokens/{oldUid}`, `joinAttempts/{oldUid}`, and the consumed
   cleanup intent when present.
7. **Returns** counts and a list of group IDs that failed (other
   groups continue). Per-group failures land in `groupsFailed` so the
   client can show a partial-success banner.

### Errors

| Code | Message | When |
|------|---------|------|
| `unauthenticated` | Sign-in required. | No `request.auth`. |
| `invalid-argument` | oldUid must be a non-empty string. | Type/length check. |
| `invalid-argument` | oldUid must differ from caller uid. | Caller passed their own UID. |
| `invalid-argument` | cleanupSecret is invalid. | Missing or malformed cleanup secret. |
| `permission-denied` | Invalid cleanup intent. | Missing, expired, or mismatched `recoveryCleanupIntents/{oldUid}`. |
| `failed-precondition` | Recovered user must be linked to an email provider. | Caller is still anonymous. |
| `failed-precondition` | Recovered user must exist before cleanup. | Auth lookup failed for any other reason. |
| `failed-precondition` | groups/{gid}.memberIds is malformed. | Schema violation in a group doc. |
| `failed-precondition` | groups/{gid}/events/{eid}.{field} is malformed. | Schema violation in an event doc. |

Per-group transaction failures are logged and added to
`groupsFailed` — they do **not** abort the rest of the cleanup. The
callable returns a partial success.

### Client wrapper

```dart
// lib/core/services/firebase_functions_service.dart
Future<void> cleanupAnonUidArtifacts({
  required String oldUid,
  required String cleanupSecret,
}) async {
  await _functions.httpsCallable('cleanupAnonUidArtifacts').call({
    'oldUid': oldUid,
    'cleanupSecret': cleanupSecret,
  });
}
```

In production this is called fire-and-forget from
`AuthRecoveryService` after it creates the cleanup intent, drains
pending writes, and completes email-link sign-in. Failures are captured
in Sentry breadcrumbs rather than blocking the user.

### Operational notes

- `cleanupAnonUidArtifacts` did not exist before v1.2.0+15. Earlier
  recovered users have residual anon-UID artifacts in their groups.
  See `docs/PRODUCT.md § Known Limitations` for the partial-cleanup
  caveat.
- The callable runs **after** the new UID is established; it cannot be
  rolled back. If per-group cleanup fails, the one-time intent remains
  until it expires so a support retry can use the same secret.

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
  fcmTokenDeleted: boolean;
  joinAttemptsDeleted: boolean;
  authUserDeleted: boolean;
}
```

### Behaviour

1. **Auth gate.** Throws `unauthenticated` if `request.auth` is null.
2. **Input gate.** Accepts only `null` or `{}`. Anything else →
   `invalid-argument`.
3. **Per-group cascade.** For each group where `memberIds` contains
   the caller's UID:
   - Generate a unique 8-char tombstone ID (`deleted-xxxxxxxx`).
   - Create `groups/{gid}/members/{tombstoneId}` with
     `displayName: "Deleted member"`, `role: 'MEMBER'`,
     `isTombstone: true`. Preserves `joinedAt` from the old member doc.
   - Delete `groups/{gid}/members/{uid}`.
   - Rewrite `groups/{gid}.memberIds`: caller's UID → tombstoneId.
   - If `createdBy == uid` and another real member exists, transfer
     creator to the oldest remaining real member. If no other real
     member exists, set `createdBy = 'deleted-user'` and soft-delete
     the group (`isDeleted: true`, `deletedAt: serverTimestamp`).
   - For each event in the group: rewrite `participantIds`,
     `participantNames`, and `createdBy` analogously.
   - For each expense: rewrite `createdBy`, `payerParticipantId`,
     `customSplitParticipants`, and `splitDistribution` keys. **Null
     out** `receiptUrl`, `note`, and `description` to scrub PII.
   - For each settlement: rewrite participant references and null out
     `note`.
   - For each activity log: rewrite `actorId`/`actorName`, rewrite
     metadata, and replace the descriptive text with
     `"Deleted member activity"`.
4. **Top-level cleanup.** Deletes `fcm_tokens/{uid}` and
   `joinAttempts/{uid}` if they exist.
5. **Auth user deletion.** Calls `getAuth().deleteUser(uid)`. If the
   user is already gone (`auth/user-not-found`),
   `output.authUserDeleted = false`. Any other failure throws
   `internal` with the cleanup output attached.
6. **Returns** a tally of everything scrubbed for client display +
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
| `invalid-argument` | deleteAccount does not accept input. | Non-empty/non-null `request.data`. |
| `failed-precondition` | `<path>` is malformed. | `memberIds` schema violation in a group doc. |
| `not-found` | Group `{id}` no longer exists. | A group disappeared mid-cascade. |
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

All three callables ship with `{ enforceAppCheck: true }`. The client
must hold a valid App Check token (Play Integrity on Android, App
Attest / DeviceCheck on iOS) or the callable returns
`unauthenticated` before any logic runs.

Debug builds and the emulator suite bypass enforcement when
`FirebaseConfig.initialize(useDebugAppCheck: true)` is called — see
`lib/main.dart:48-50`. The release pipeline gates on the
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
(`lib/main.dart:56-67`) auto-detects Android emulators (uses
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
| `functions/src/index.ts` | 9 | Region + exports |
| `functions/src/admin.ts` | 3 | `initializeApp()` side-effect |
| `functions/src/callables/joinGroupByInviteCode.ts` | 313 | Invite-code redemption + event fan-out |
| `functions/src/callables/cleanupAnonUidArtifacts.ts` | 271 | Anon→recovered UID migration |
| `functions/src/callables/deleteAccount.ts` | 551 | Account deletion cascade + tombstones |
| `functions/package.json` | — | Node 20 / TypeScript / Jest |
| `functions/jest.config.js` | — | Test config |
| `lib/core/services/firebase_functions_service.dart` | 20 | Flutter client wrapper |
| `security/firestore.rules` | 725 | Companion rules; see [SECURITY-RULES.md](./SECURITY-RULES.md) |

---

## Related docs

- [SECURITY-RULES.md](./SECURITY-RULES.md) — what's enforced at the rules layer
- [ACCOUNT-RECOVERY.md](./ACCOUNT-RECOVERY.md) — how `cleanupAnonUidArtifacts` fits the recovery flow
- [RUNBOOK.md](./RUNBOOK.md) — tripwires T2 and T3 cover Cloud Functions error rates
- [PRODUCTION-READINESS.md](./PRODUCTION-READINESS.md) — pre-deploy checklist
- [ARCHITECTURE.md](./ARCHITECTURE.md) — overall system picture
