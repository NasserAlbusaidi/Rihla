# Firestore Security Rules

Reference for `security/firestore.rules` — the only file Firestore
evaluates when a client tries to read or write. Cloud Functions use the
Admin SDK and bypass these rules entirely; see
[CLOUD-FUNCTIONS.md](./CLOUD-FUNCTIONS.md) for the server-side
authorization checks that fill the gap.

Rules version is `2`. The file is **default-deny** — anything not
explicitly allowed is refused.

---

## 1. Quick reference

| Collection | Read | Create | Update | Delete |
|------------|------|--------|--------|--------|
| `/{document=**}` (default) | ❌ | ❌ | ❌ | ❌ |
| `fcm_tokens/{userId}` | owner only | owner only | owner only | owner only |
| `inviteCodes/{code}` | ❌ (callable only) | group creator, with companion group write | ❌ (immutable) | group creator, with companion group delete |
| `joinAttempts/{userId}` | ❌ (admin only) | ❌ | ❌ | ❌ |
| `deletionAttempts/{userId}` | ❌ (admin only) | ❌ | ❌ | ❌ |
| `deletionAudit/{userId}` | ❌ (admin only) | ❌ | ❌ | ❌ |
| `recoveryCleanupIntents/{oldUid}` | ❌ (callable only) | retiring UID, secret 32-128 chars + `expiresAt` (#170 TTL) | retiring UID (same shape) | ❌ (callable only) |
| `groups/{gid}` | members | self, valid initial doc | creator metadata / member-list refresh / self-leave / creator-remove | creator |
| `groups/{gid}/members/{mid}` | members | members (with self-rules) | self displayName only | self-leave or creator-remove |
| `groups/{gid}/activity/{aid}` | members | members (actor must be self) | ❌ | ❌ |
| `groups/{gid}/settlements/{sid}` (group-level) | members | members (creator must be self) | ❌ (B3 append-only) | ❌ (B3 append-only) |
| `groups/{gid}/events/{eid}` | members | members | event participants (light) / event-or-group creator (admin) | ❌ (soft-delete only) |
| `groups/{gid}/events/{eid}/expenses/{xid}` | members | event participants (creator must be self) | record creator, allowed-fields, soft-delete one-way | ❌ |
| `groups/{gid}/events/{eid}/settlements/{sid}` | members | event participants (creator must be self) | ❌ (B3) | ❌ (B3) |
| `groups/{gid}/events/{eid}/activity_logs/{aid}` | members | event participants (actor must be self) | ❌ | ❌ |

"Member" means `request.auth.uid in groups/{gid}.memberIds`. "Creator"
means `request.auth.uid == groups/{gid}.createdBy`. Sign-in is anonymous
Firebase Auth.

---

## 2. Helper functions

The rules file defines reusable predicates near the top of the
`databases/{database}/documents` match:

| Function | Returns | Notes |
|----------|---------|-------|
| `signedIn()` | `request.auth != null` | All other helpers require this. |
| `nullableString(v)` | `v == null || v is string` | For optional text fields. |
| `isValidDisplayName(s)` | 1-32 char string, no control chars, no `(former member)` suffix | Mirrors the client-side `validateDisplayName` in `lib/core/utils/name_validators.dart`. **Both must be edited together.** |
| `isValidNullableDisplayName(s)` | `s == null || isValidDisplayName(s)` | For optional snapshot fields like `payerName`. |
| `displayNameMapValuesAreValid(m)` | Every value in `m` passes `isValidDisplayName` | Validates `event.participantNames`. Implemented by joining values on `'\n'` and asserting against a regex — Firestore Rules has no map iteration. |
| `validCurrency(v)` | `v is string && v.size() == 3` | ISO 4217 length check; does not enforce a whitelist. |
| `positiveInt(v)` | `v is int && v > 0` | For money subunits (`amountFils`). |
| `groupPath(gid)` | Path to `/groups/{gid}` | Avoids string concatenation in every rule. |
| `groupData(gid)` | `get(groupPath).data` | Current Firestore state. |
| `groupAfterData(gid)` | `getAfter(groupPath).data` | State after the in-flight write commits — needed for cross-doc invariants. |
| `isGroupMember(gid)` | Group exists and caller is in `memberIds` | Used as the read gate on subcollections. |
| `isGroupCreator(gid)` | Group exists and caller is `createdBy` | Used for elevated operations. |
| `eventPath(gid, eid)` / `eventData(gid, eid)` | Path / data helpers for event docs | |
| `isEventParticipant(gid, eid)` | Event exists and caller is in `participantIds` | The expense/settlement write gate. |
| `requesterIsRecordCreator()` | `resource.data.createdBy == request.auth.uid` | The B1 ownership check for expenses and settlements. |

`get` and `getAfter` cost one document read per invocation and Firestore
caps them at 10 per request. The rules are carefully written to stay
under that cap — for example, `isGroupMember(gid)` reuses
`groupData(gid)` rather than fetching the doc twice.

---

## 3. Cross-cutting invariants

These guardrails apply across multiple collections. They are the
"OS-level" guarantees of the data model.

### B1 — Money record ownership (creator-only edit)

Every expense and settlement carries `createdBy` (auth UID). The field
is **immutable** after creation. Only the creator can update or
soft-delete their own record.

```
function requesterIsRecordCreator() {
  return signedIn() && resource.data.createdBy == request.auth.uid;
}
```

Implication: anyone in an event can create a record naming someone else
as `payerParticipantId`, but only the creator can later modify it. If
forging false claims becomes a real problem, B2 (peer acknowledgement)
and B3 (immutable settlements) would need to be revisited.

### B3 — Settlements are append-only

Both event-level (`groups/{gid}/events/{eid}/settlements/{sid}`) and
group-level (`groups/{gid}/settlements/{sid}`) settlements deny
`update` and `delete`. Corrections happen by writing a new offsetting
settlement, not by mutating the old one. This preserves an audit trail
for money movement.

The expense rules permit updates and soft-deletes by the creator; only
settlements are absolute.

### Identity rewrites vs. financial immutability (Admin-SDK maintenance)

B1 (immutable `createdBy`) and B3 (append-only settlements) bind **peers**.
Two callables write *through* those rules via the Admin SDK, which bypasses
the rule engine entirely (see the §1 header and §5): `cleanupAnonUidArtifacts`
repoints a recovered user's `oldUid → newUid` (same human, after email-link
recovery — §4.3b), and `deleteAccount` repoints a departing `uid → tombstone`
(§4.3a). Neither is gated by B1/B3.

The contract that keeps server-side re-identification safe — **and that no
rule enforces** — is: *these callables may repoint **identity** fields, but
they never alter a monetary amount, its currency, or the payer→recipient
direction of a settlement.* A future cleanup/deletion refactor that wrote an
amount field would silently corrupt money with no rule to stop it, so it is
pinned here.

**Identity fields the Admin SDK MAY rewrite** (verified against the callables):

| Field (record) | Peer rule | `cleanupAnonUidArtifacts` (recovery) | `deleteAccount` (deletion) |
|---|---|---|---|
| `createdBy` (group/event/expense/settlement) | immutable (B1) | `oldUid→newUid` | `uid→` sentinel (group keeps a remaining real creator if any) |
| `memberIds` (group) | admin-update shape only | `oldUid→newUid` (dedup) | `uid` removed / tombstoned |
| `participantIds` (event) | light/admin update | `oldUid→newUid` (dedup) | `uid→` tombstone |
| `participantNames` **keys** (event) | — | key `oldUid→newUid` | key `uid→` tombstone |
| `payerParticipantId` (expense/settlement) | set at create; not the B1 key | `oldUid→newUid` | `uid→` tombstone |
| `recipientParticipantId` (settlement) | set at create | `oldUid→newUid` | `uid→` tombstone |
| `customSplitParticipants` (expense) | — | `oldUid→newUid` (dedup) | — |
| `splitDistribution` **keys** (expense) | values ≥ 0 (#192) | key `oldUid→newUid`; **sum-merge** on collision | key `uid→` tombstone |
| `payerName` / `recipientName` (settlement, denormalized) | — | left untouched (same person) | scrubbed to `Deleted member` |
| member subdoc `id` / `userId` | — | copied to `newUid` doc, old deleted | tombstoned |

**Financial fields that NEVER change — even under the Admin SDK** (these appear
in **no** update map in either callable):

| Field | Records | Guarantee |
|---|---|---|
| `amountFils` | expense, settlement | the monetary value (integer subunits via `MoneySerializer`) is never written by recovery or deletion |
| `currency` | expense, settlement | never rewritten |
| `scope` / `splitMode` | expense (`scope` also settlement) | never rewritten |
| `splitDistribution` **values** | expense | only keys are renamed; values are preserved, and recovery **sums** colliding subunits so the share total / denominator is conserved — never re-weighted |
| payer→recipient **pairing/direction** | settlement | the pair is only *relabeled* (`oldUid→newUid` or `uid→`tombstone); it is never swapped, so "who owes whom" is preserved |

Peer creates are additionally floored by the rules — `positiveInt(amountFils)`
and `payerParticipantId != recipientParticipantId` (settlement create),
non-negative `splitDistribution` values (#192). The Admin SDK is not bound by
those floors; the table above is the discipline that substitutes for them on
the server paths.

> Sources (verify before relying): rewrites — `functions/src/callables/cleanupAnonUidArtifacts.ts`
> (`settlementMigrationUpdate`, `mergeUidMapKey`, `processGroup`) and
> `functions/src/callables/deleteAccount.ts` (`renameMapKey`, the expense /
> settlement / event / group update builders). Field names —
> `Expense.toFirestore` / `Settlement.toFirestore` in `lib/features/ledger/models/`.

### Soft delete is one-way

For collections that support soft delete (events, expenses), the
`isDeleted: false → true` transition is allowed once per row. Going the
other direction is forbidden by an explicit check in `validSoftDelete`
/ admin update:

```
resource.data.isDeleted == false
&& request.resource.data.isDeleted == true
```

There is no resurrection path. To restore data, you write a new row.

### Default deny

```
match /{document=**} {
  allow read, write: if false;
}
```

Any collection without an explicit `match` rule is sealed. Adding a new
collection requires explicitly opening it.

---

## 4. Per-collection rules

### 4.1 `fcm_tokens/{userId}`

Owner-only read and write. Document ID equals the user's UID.

```
match /fcm_tokens/{userId} {
  allow read, write: if signedIn() && request.auth.uid == userId;
}
```

Used by the FCM token sync logic in `NotificationService`. No schema
validation — the rule trusts the owner with their own token doc.

### 4.2 `inviteCodes/{code}`

Server-only read; tightly-scoped client writes. Direct client reads are
**denied** so codes cannot be brute-forced from Firestore. The
`joinGroupByInviteCode` callable (Admin SDK) is the only path to
redeem.

| Op | Allowed if |
|----|------------|
| `get`, `list` | ❌ |
| `create` | Caller is the creator of the group named in `groupId`. The matching group must exist *after* the write and its `inviteCode` must equal `{code}`. Doc may only contain `groupId` (string) + `createdAt` (timestamp). |
| `update` | ❌ |
| `delete` | Either the underlying group is already gone (cleanup case), or the caller is the group's creator and they are simultaneously deleting the group. |

The "delete if the group is gone" branch is a self-heal: a stale invite
doc with no surviving group can be cleaned up by any signed-in user.
This came out of a v1.1 bug where deletion failures left dangling
invite docs.

### 4.3 `joinAttempts/{userId}`

Fully sealed to clients:

```
match /joinAttempts/{userId} {
  allow read, write: if false;
}
```

Read and written only by the `joinGroupByInviteCode` callable to
enforce the 5-failures-per-hour lockout. Clients never see lockout
state directly; they get back `resource-exhausted` from the callable.

### 4.3a `deletionAttempts/{userId}`

Fully sealed to clients:

```
match /deletionAttempts/{userId} {
  allow read, write: if false;
}
```

Written only by the `deleteAccount` callable (via the Admin SDK, which
bypasses these rules) to enforce a per-UID deletion-invocation rate
limit (#73). Clients can never read or write these counters. A Firestore
TTL on `expiresAt` reaps the rows.

### 4.3a-2 `deletionAudit/{userId}`

Fully sealed to clients:

```
match /deletionAudit/{userId} {
  allow read, write: if false;
}
```

Written only by the `deleteAccount` callable and the `deletionReaper`
scheduled function (via the Admin SDK) to mark an **incomplete** account
deletion so the reaper can finish abandoned/timed-out deletions (#76). The
marker is deleted once the deletion converges; a Firestore TTL on
`expiresAt` is the safety net. Clients never read or write it.

### 4.3b `recoveryCleanupIntents/{oldUid}`

Not sealed — the retiring anonymous UID may write a one-time bearer
secret (`validCleanupIntent`):

```
match /recoveryCleanupIntents/{oldUid} {
  allow create, update: if validCleanupIntent();
  allow get, list, delete: if false;
}
```

`validCleanupIntent` requires:

- Caller is signed in and `request.auth.uid == {oldUid}` (only the
  retiring UID can write its own intent)
- Exact key set `{secret, createdAt, expiresAt}`
- `secret` is a string of length 32–128
- `createdAt` is a timestamp
- `expiresAt` is a timestamp **strictly after** `createdAt` (#170)

`get`, `list`, and `delete` are denied to clients. The intent is read
and consumed server-side by the `cleanupAnonUidArtifacts` callable,
which performs the UID rewrite after email-link recovery.

**TTL (#170):** the client writes `expiresAt = now + 24h`; a Firestore
TTL on `recoveryCleanupIntents.expiresAt` (declared in
`firestore.indexes.json`) reaps abandoned bearer-secret docs. The 24h
window is deliberately longer than the 15-minute server validity
(`cleanupIntentMaxAgeMs` in `cleanupAnonUidArtifacts.ts`) so a TTL never
reaps a still-valid intent under client clock skew. **Validity stays
keyed on `createdAt`, not `expiresAt`** — the server never reads
`expiresAt`; it is purely a GC marker.

### 4.4 `groups/{gid}`

#### Read

Any member can read. Non-members get permission-denied — including
when they're trying to *check* if they're a member.

```
allow read: if isMember();
```

#### Create (`validGroupCreate`)

The caller creates the group with themselves as the only member. The
new doc must contain *exactly* this key set:

```
['id', 'name', 'inviteCode', 'createdBy', 'memberIds',
 'currency', 'createdAt', 'updatedAt']
```

Additional invariants:

- `id == {gid}` (Firestore doc ID matches the field)
- `name` passes `isValidDisplayName`
- `createdBy == request.auth.uid`
- `memberIds == [request.auth.uid]` (you cannot pre-seed members)
- `currency` is a 3-char string
- Timestamps present

#### Update (four allowed shapes)

| Shape | Function | Who |
|-------|----------|-----|
| Metadata edit | `validCreatorMetadataUpdate` | Creator. Affected keys ⊆ `{name, currency, updatedAt}`; `name` validates if present; `currency` validates if present. |
| Member-list refresh | `validMemberIdsRefresh` | Any member. `memberIds` unchanged + bump `updatedAt`. Used by clients to refresh the `updatedAt` ordering signal without mutating membership. |
| Self-leave | `validSelfLeave` | Member removing themselves. Exactly one element drops from `memberIds` and that element is the caller. |
| Creator-remove-member | `validCreatorRemoveMember` | Creator removing someone else. Exactly one element drops and that element is **not** the caller (so creators cannot leave their own group while members remain). |

The "exactly one drop" predicate (`removesExactlyOneExistingMember`)
ensures the entire `memberIds` array is preserved minus a single
element — clients cannot smuggle in a different list under cover of a
membership change.

#### Delete

```
allow delete: if isCreator();
```

Hard-delete. Used by the creator's "Delete group" action. Cascading
deletion of subcollections is the client's responsibility — Firestore
itself does not cascade.

### 4.5 `groups/{gid}/events/{eid}` (C-Hierarchy)

Events have two update paths reflecting a two-tier permission model.

#### Read

```
allow read: if isGroupMember(gid);
```

All group members read all events, even ones they aren't a participant
in (so the group detail screen can list every event).

#### Create (`validEventCreate`)

Caller must be a group member. The new doc must contain exactly these
keys:

```
['name', 'type', 'groupId', 'createdBy', 'participantIds',
 'participantNames', 'modules', 'startDate', 'endDate',
 'isDeleted', 'deletedAt', 'createdAt', 'serverCreatedAt',
 'updatedAt', 'description']
```

`validEventBase` enforces:

- `name` valid display name
- `type` in `['trip', 'camping', 'travel', 'night_day_out', 'custom']`
- `groupId == {gid}`
- `participantIds` non-empty, all UIDs are members of the group
- `participantNames` is a map whose values all pass `isValidDisplayName`
- `modules` is a map with the single key `ledger: bool` (Phase 39 lock)
- Optional `startDate`, `endDate` are nullable timestamps
- `description` is nullable string
- `isDeleted: false`, `deletedAt: null` at create time
- Caller must include themselves in `participantIds`

`modules.keys().hasOnly(['ledger'])` is what prevents reintroduction of
the stripped gear/logistics/memories/vault modules at the schema level.

#### Update — light path (`validEventLightUpdate`)

Any current event participant. May edit only these fields:

```
['name', 'participantIds', 'participantNames', 'startDate',
 'endDate', 'updatedAt', 'description']
```

Additional constraints:

- Cannot remove participants — `participantIds` must contain all
  existing IDs. Adding is fine.
- Cannot rename or delete entries in `participantNames` — only adding
  new entries.

This is the "any participant can update event metadata" path: rename
the event, extend the date range, add a description, add a participant.

> **Decision (#57): additive participant-add is the intended collaboration model.**
> Any event participant may *add* members to an event; removing and renaming are
> admin-only. This is deliberate — events are collaborative and people on a trip
> routinely add each other. **Abuse boundary:** added IDs are constrained to
> **existing group members** — the light path calls `validEventUpdateCommon()` →
> `validEventBase()`, which enforces `participantIds.hasOnly(groupMembers())`. So
> the blast radius is in-group griefing (a member adding another member to an
> event), never outsider injection. The join fan-out (`joinGroupByInviteCode`) is
> a *self*-add, not a third-party add. If this ever needs tightening, move adds
> behind `validEventAdminUpdate` or a controlled callable rather than widening the
> light path. Full record: `docs/adr/ADR-0002-event-participant-add.md`.

#### Update — admin path (`validEventAdminUpdate`)

Event creator **OR** group creator. May edit a superset:

```
['name', 'participantIds', 'participantNames', 'modules',
 'startDate', 'endDate', 'isDeleted', 'deletedAt', 'updatedAt',
 'description']
```

Plus: can remove participants, edit `modules`, and perform the one-way
`isDeleted: false → true` transition (along with `deletedAt: timestamp`).

The soft-delete sub-rule is strict:

```
request.resource.data.diff(resource.data).affectedKeys()
  .hasOnly(['isDeleted', 'deletedAt', 'updatedAt'])
&& resource.data.isDeleted == false
&& request.resource.data.isDeleted == true
&& request.resource.data.deletedAt is timestamp
```

#### Delete

```
allow delete: if false;
```

No hard-delete. Use the soft-delete update path.

### 4.6 `groups/{gid}/events/{eid}/{module}/{docId}`

A polymorphic match for the three event subcollections — `expenses`,
`settlements`, `activity_logs`. The `{module}` segment selects which
validator runs.

#### Read

```
allow read: if isGroupMember(gid)
  && module in ['expenses', 'settlements', 'activity_logs'];
```

Any group member can read any of the three. Other module names get a
permission-denied (this is what locks out attempts to read the
stripped `gear` / `vault` / `logistics` / `memories` subcollections).

#### Create

`allow create: if validExpenseCreate() || validEventSettlementCreate() || validActivityCreate();`

Each branch enforces the module name plus its own schema.

**Expenses** (`validExpenseBase` + `validExpenseCreate`):

- Exact key set: `id, eventId, createdBy, payerParticipantId, amountFils, currency, description, scope, subGroupId, customSplitParticipants, splitMode, splitDistribution, receiptUrl, categoryId, note, isDeleted, deletedAt, createdAt`
- `id == {docId}`, `eventId == {eid}`
- `payerParticipantId in event.participantIds`
- `amountFils` is a positive int (money is stored as subunits — see [ARCHITECTURE.md § Financial Calculations](./ARCHITECTURE.md))
- `currency` is a 3-char string
- `scope in ['global', 'sub_group', 'personal', 'custom']`
- `customSplitParticipants` is a list whose elements are all event participants
- `splitMode in ['equally', 'shares', 'exact', 'percent']` (if present)
- Optional string fields: `subGroupId`, `description`, `note`, `receiptUrl`, `categoryId`
- `isDeleted: false`, `deletedAt: null` at create
- `createdBy == request.auth.uid` and caller `isEventParticipant`

**Event settlements** (`validEventSettlementBase` + `validEventSettlementCreate`):

- Exact key set: `id, eventId, createdBy, payerParticipantId, recipientParticipantId, amountFils, currency, note, isDeleted, deletedAt, settledAt`
- Payer and recipient must both be participants AND different from each other
- `amountFils` positive int, `currency` 3-char string
- `createdBy == request.auth.uid` and caller `isEventParticipant`

**Activity logs** (`validActivityCreate`):

- Exact key set: `id, eventId, category, eventType, logText, actorId, actorName, metadata, createdAt`
- `actorId == request.auth.uid` (actor must be self)
- `actorName` is a valid display name (or null)
- `category`, `eventType`, `logText` are strings; `metadata` is a map; `createdAt` is a string

#### Update

Only expenses are updatable (`validExpenseUpdate`):

- Caller is event participant **and** record creator (B1)
- `createdBy` cannot change
- Affected keys ⊆ `{payerParticipantId, amountFils, currency, description, scope, subGroupId, customSplitParticipants, splitMode, splitDistribution, receiptUrl, categoryId, note, isDeleted, deletedAt}`
- The full base validator runs against the new state
- The `isDeleted` / `deletedAt` pair must either both stay the same OR perform the one-way soft-delete

#### Delete

```
allow delete: if false;
```

Hard-delete is forbidden; use the soft-delete update path.

#### Nested deeper subcollections

```
match /{nestedCol}/{nestedDocId} {
  allow read, write: if false;
}
```

Anything below `groups/{gid}/events/{eid}/{module}/{docId}/` is sealed.
This prevents accidentally exposing future child collections.

### 4.7 `groups/{gid}/events/{eid}/settlements/{sid}` (B3 override)

The polymorphic `{module}` create rule above never references a
settlement-update validator, and this explicit `allow update/delete: if
false` enforces B3. Note: `validEventSettlementUpdate` /
`validGroupSettlementUpdate` are defined in the rules file but are
intentionally left unwired (dead) — B3 keeps settlements append-only, so
no `allow update` clause ever calls them. The rules add this explicit
match to make B3 visible:

```
match /settlements/{settlementId} {
  allow update: if false;  // B3: settlements are append-only.
  allow delete: if false;  // B3: settlements are append-only.
}
```

This is documentation-via-code: B3 is the load-bearing invariant of
the audit trail.

### 4.8 `groups/{gid}/members/{memberId}`

| Op | Allowed if |
|----|------------|
| `read` | Any group member. |
| `create` (`validMemberCreate`) | Caller is a group member. New doc keys ⊆ `{id, userId, displayName, role, joinedAt, isShadow}`. `id == {memberId}`, `userId == request.auth.uid`, `displayName` valid, `role` in `['CREATOR', 'MEMBER']`. `CREATOR` role allowed only when caller is the group's `createdBy`. |
| `update` (`validSelfDisplayNameUpdate`) | Caller owns the member doc (`resource.data.userId == request.auth.uid`). Affected keys = `{displayName}` only. |
| `delete` (`validMemberDelete`) | Either self-leave (caller's UID dropped from group's `memberIds` in the same transaction) or creator-remove (caller is group creator and target UID is being dropped from `memberIds` or the group is being deleted entirely). |

The cross-doc `getAfter` checks make the member doc deletion atomic
with the group's `memberIds` update — you cannot delete a member doc
without simultaneously reflecting the leave in the parent group, and
vice versa.

### 4.9 `groups/{gid}/activity/{activityId}` (group-level)

```
allow read: if isGroupMember(gid);
allow create: if validGroupActivityCreate();  // actor must be self
allow update, delete: if false;
```

Append-only audit log for group-scoped events (member joined, group
renamed, etc.). `validGroupActivityCreate` enforces the exact key set
and `actorId == request.auth.uid`.

### 4.10 `groups/{gid}/settlements/{sid}` (group-level, B3)

Same shape as event-level settlements but scoped to the group. Used
for cross-event settle-ups.

```
allow read: if isGroupMember(gid);
allow create: if validGroupSettlementCreate();
allow update: if false;  // B3
allow delete: if false;  // B3
```

`validGroupSettlementBase` enforces:

- Exact key set: `id, groupId, eventId, createdBy, scope, payerParticipantId, recipientParticipantId, amountFils, currency, note, payerName, recipientName, isDeleted, deletedAt, settledAt`
- `groupId == {gid}` and `eventId == {gid}` (yes — group settlements
  intentionally set `eventId` to the group ID to keep the shape
  uniform with event settlements)
- `scope == 'group'`
- Payer and recipient must both be in `memberIds` and different
- `payerName` / `recipientName` are nullable valid display names (snapshot of who paid/received at the time of the settlement)

---

## 5. What the rules do **not** enforce

These are conscious omissions; the listed callable or invariant carries
the check instead. For what the `deleteAccount` and `cleanupAnonUidArtifacts`
callables may and may not rewrite once they bypass the rules, see
[Identity rewrites vs. financial immutability](#identity-rewrites-vs-financial-immutability-admin-sdk-maintenance) in §3.

| Concern | Why not in rules | Carried by |
|---------|------------------|------------|
| Invite-code redemption | A rule cannot atomically read `inviteCodes` + add to `memberIds` + fan out into all events while staying under the `get` budget. | `joinGroupByInviteCode` callable. |
| Rate-limiting failed joins | Rules cannot increment a counter across requests. | `joinAttempts` doc, written by the callable. |
| Account deletion cascade | Cross-collection scrub across hundreds of docs exceeds rules' write surface. | `deleteAccount` callable. |
| UID migration after recovery | Same. Rules only let the retiring anon UID create/update a one-time `recoveryCleanupIntents/{oldUid}` secret; the Admin callable performs the actual rewrite after verifying it. | `cleanupAnonUidArtifacts` callable. |
| Currency whitelist | `validCurrency` checks length only; the actual allowed set (OMR/USD/EUR/GBP/SAR/AED/JPY/KWD/BHD/QAR) lives in `MoneySerializer`. | Client validation + `MoneySerializer`. |
| Money math correctness | Rules can validate fields, not arithmetic. | `BalanceCalculator` + unit tests under `test/unit/`. |
| Server-side App Check enforcement | Rules don't see App Check tokens. | `{ enforceAppCheck: true }` on every callable. |

---

## 6. Working on the rules

### Edit ↔ test loop

```bash
# Start the Firestore emulator + Functions
cd functions && firebase emulators:start --only firestore,auth,functions

# In a second terminal — run rule tests against the running emulator
cd functions && npm test
```

Rule tests are under `functions/test/` and run via Jest under Java 21
(the emulator itself needs Java 21 too). Tests use
`@firebase/rules-unit-testing` to spin up authenticated and
unauthenticated contexts against the running emulator.

### Deploy

Rules deploy as part of the backend deployment script:

```bash
RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA="$(git rev-parse HEAD)" bash tool/deploy_firebase_backend.sh rihla-safar
```

The script also requires a clean worktree plus commit-bound approved SHA, then
diffs current production rules against the repo after deploy verification. See
[RUNBOOK.md § T2](./RUNBOOK.md) for the rules-drift incident response.

### Aligning `isValidDisplayName` with the client

The client mirror lives in `lib/core/utils/name_validators.dart` (the
function `isValidDisplayName`). The two must stay aligned — a client
that accepts a name the rules later reject produces a Firestore write
that fails locally before it ever leaves the device. Search for
`isValidDisplayName` across both files when changing the contract.

---

## 7. Files at a glance

| File | Purpose |
|------|---------|
| `security/firestore.rules` | The rules themselves (this doc) |
| `functions/test/*.test.ts` | Rule tests via `@firebase/rules-unit-testing` |
| `firestore.indexes.json` (project root) | Companion index spec |
| `tool/deploy_firebase_backend.sh` | Production rules + indexes + functions deploy |
| `tool/check_firebase_prod_state.sh` | Pre-deploy drift check |
| `lib/core/utils/name_validators.dart` | `isValidDisplayName` client mirror |
| `lib/core/services/money_serializer.dart` | Currency whitelist (client-only) |
| `functions/src/callables/*.ts` | Admin-SDK callables that bypass these rules |

---

## 8. Related docs

- [CLOUD-FUNCTIONS.md](./CLOUD-FUNCTIONS.md) — the callables that bypass rules
- [ARCHITECTURE.md](./ARCHITECTURE.md) — overall data model (groups → events → expenses/settlements/activity)
- [PRODUCT.md](./PRODUCT.md) — domain model (B1 ownership, B3 append-only)
- [RUNBOOK.md](./RUNBOOK.md) — incident response for rules drift / Functions errors
- [PRODUCTION-READINESS.md](./PRODUCTION-READINESS.md) — pre-deploy checklist
