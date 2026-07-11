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
| `groups/{gid}` | members | self, valid initial doc | current-member creator metadata (#1132) / member-list refresh | ❌ (server soft-delete only) |
| `groups/{gid}/members/{mid}` | members | members (with self-rules) | self displayName only | self, or current-member creator for a non-member (shadow) doc (#1132); after server-authoritative memberIds removal |
| `groups/{gid}/activity/{aid}` | members | members (actor must be self) | ❌ | ❌ |
| `groups/{gid}/settlements/{sid}` (group-level) | members | members (creator must be self) | ❌ (B3 append-only) | ❌ (B3 append-only) |
| `groups/{gid}/events/{eid}` | members | members | event participants (light) / current-member event-or-group creator (admin, #1132) | ❌ (soft-delete only) |
| `groups/{gid}/events/{eid}/expenses/{xid}` | members | member + event participant (creator must be self, #1131) | member + event participant, allowed-fields, soft-delete one-way (#1131) | ❌ |
| `groups/{gid}/events/{eid}/settlements/{sid}` | members | members (creator must be self; counterparties must be event participants, #752) | ❌ (B3) | ❌ (B3) |
| `groups/{gid}/events/{eid}/activity_logs/{aid}` | members | ❌ (server audit trigger only) | ❌ | ❌ |

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
| `validCurrency(v)` | supported ISO code allowlist | Matches the app's supported storage/display currencies. |
| `positiveInt(v)` | `v is int && v > 0` | For money subunits (`amountFils`). |
| `groupPath(gid)` | Path to `/groups/{gid}` | Avoids string concatenation in every rule. |
| `groupData(gid)` | `get(groupPath).data` | Current Firestore state. |
| `groupAfterData(gid)` | `getAfter(groupPath).data` | State after the in-flight write commits — needed for cross-doc invariants. |
| `isGroupMember(gid)` | Group exists and caller is in `memberIds` | The read gate on subcollections; since #1131 also a conjunct on expense writes. |
| `isGroupCreator(gid)` | Group exists and caller is `createdBy` | Dead helper — zero callers (the group-scoped `isCreator`/`requesterIsGroupCreator` do this inline). Creator authority also requires current membership since #1132. |
| `eventPath(gid, eid)` / `eventData(gid, eid)` | Path / data helpers for event docs | |
| `isEventParticipant(gid, eid)` | Event exists and caller is in `participantIds` | One half of the expense write gate — paired with `isGroupMember` since #1131 (`participantIds` is never pruned on departure, so participation alone is not current membership). |
| `requesterIsRecordCreator()` | `resource.data.createdBy == request.auth.uid` | Retained settlement-corrections scaffold; live settlement updates are hard-denied and live expense updates no longer call it. |

`get` and `getAfter` cost one document read per invocation and Firestore
caps them at 10 per request. The rules are carefully written to stay
under that cap — for example, `isGroupMember(gid)` reuses
`groupData(gid)` rather than fetching the doc twice.

---

## 3. Cross-cutting invariants

These guardrails apply across multiple collections. They are the
"OS-level" guarantees of the data model.

### B1 — Money record authorship

Every expense and settlement carries `createdBy` (auth UID). The field
is **immutable** after creation.

Expense edits are now open-edit: any current group member who is an event
participant may update or soft-delete any expense through `validExpenseUpdate`
(#1131 added the `isGroupMember` conjunct — departure/removal never prunes
event `participantIds`, so participation alone must not grant writes). The
editor is pinned by `lastEditedBy == request.auth.uid`, and the
`expenseAuditLogger` trigger logs the change. Settlements stay append-only;
corrections are new offsetting rows.

```
function requesterIsRecordCreator() {
  return signedIn() && resource.data.createdBy == request.auth.uid;
}
```

`requesterIsRecordCreator()` is retained only for dead settlement-update helper
paths kept as settlement-corrections scaffolding. Those match blocks still
hard-deny update, so the helper is not part of live expense authorization.

Implication: any current member in an event can create a record naming someone
else as `payerParticipantId`, and any current-member event participant can
later modify the expense within the allowed field/value guards. If forging false claims becomes a real
problem, B2 (peer acknowledgement), the future `ledgerEditPolicy`, and B3
(append-only settlements) would need to be revisited.

### B3 — Settlements are append-only

Both event-level (`groups/{gid}/events/{eid}/settlements/{sid}`) and
group-level (`groups/{gid}/settlements/{sid}`) settlements deny
`update` and `delete`. Corrections happen by writing a new offsetting
settlement, not by mutating the old one. This preserves an audit trail
for money movement.

The expense rules permit updates and soft-deletes by current-member event
participants (#1131); only settlements are absolute.

### Identity rewrites vs. financial immutability (Admin-SDK maintenance)

B1 (immutable `createdBy`) and B3 (append-only settlements) bind **peers**.
The `deleteAccount` callable writes *through* those rules via the Admin SDK,
which bypasses the rule engine entirely (see the §1 header and §5):
`deleteAccount` repoints a departing `uid → tombstone` (§4.3a). It is not
gated by B1/B3. (The `cleanupAnonUidArtifacts` cross-UID migration callable
was deleted in #441 PR5.)

The contract that keeps server-side re-identification safe — **and that no
rule enforces** — is: *these callables may repoint **identity** fields, but
they never alter a monetary amount, its currency, or the payer→recipient
direction of a settlement.* A future cleanup/deletion refactor that wrote an
amount field would silently corrupt money with no rule to stop it, so it is
pinned here.

**Identity fields the Admin SDK MAY rewrite** (verified against the callables):

| Field (record) | Peer rule | `deleteAccount` (deletion) |
|---|---|---|
| `createdBy` (group/event/expense/settlement) | immutable (B1) | `uid→` sentinel (group keeps a remaining real creator if any) |
| `memberIds` (group) | admin-update shape only | `uid` removed / tombstoned |
| `participantIds` (event) | light/admin update | `uid→` tombstone |
| `participantNames` **keys** (event) | — | key `uid→` tombstone |
| `payerParticipantId` (expense/settlement) | set at create; not the B1 key | `uid→` tombstone |
| `recipientParticipantId` (settlement) | set at create | `uid→` tombstone |
| `customSplitParticipants` (expense) | — | — |
| `splitDistribution` **keys** (expense) | values ≥ 0 (#192) | key `uid→` tombstone |
| `payerName` / `recipientName` (settlement, denormalized) | — | scrubbed to `Deleted member` |
| member subdoc `id` / `userId` | — | tombstoned |

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

> Sources (verify before relying): rewrites — `functions/src/callables/deleteAccount.ts`
> (`renameMapKey`, the expense / settlement / event / group update builders).
> Field names — `Expense.toFirestore` / `Settlement.toFirestore` in `lib/features/ledger/models/`.
> (`cleanupAnonUidArtifacts` was deleted in #441 PR5.)

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

### 4.4 `groups/{gid}`

#### Read

Any member can read. Non-members get permission-denied — including
when they're trying to *check* if they're a member.

```
allow read: if isMember();
```

#### Create (`validGroupCreate`)

The caller creates the group with themselves as the only member. The
new doc's keys must be within this allowlist:

```
['id', 'name', 'inviteCode', 'createdBy', 'memberIds',
 'currency', 'createdAt', 'updatedAt', 'isDeleted', 'deletedAt',
 'glyph', 'inkIndex']
```

Additional invariants:

- `id == {gid}` (Firestore doc ID matches the field)
- `name` passes `isValidDisplayName`
- `createdBy == request.auth.uid`
- `memberIds == [request.auth.uid]` (you cannot pre-seed members)
- `currency` passes the supported-code `validCurrency` allowlist
- Timestamps present
- `isDeleted == false`, `deletedAt == null`
- `glyph` / `inkIndex` are optional; each present value must pass its
  trip-stamp allowlist

#### Update (two allowed shapes)

| Shape | Function | Who |
|-------|----------|-----|
| Metadata edit | `validCreatorMetadataUpdate` | Creator. Affected keys ⊆ `{name, updatedAt, glyph, inkIndex}`; `name` validates if present; `glyph` / `inkIndex` must be absent-or-valid. `currency` is immutable after create. |
| Member-list refresh | `validMemberIdsRefresh` | Any member. `memberIds` unchanged + bump `updatedAt`. Used by clients to refresh the `updatedAt` ordering signal without mutating membership. |

Direct client membership removal is forbidden. `leaveGroup` and
`removeMember` are server-authoritative Cloud Functions that recompute the
leaver/target balance, refuse non-zero net, then remove the UID from
`memberIds` and delete the member doc in an Admin SDK batch.

#### Delete

```
allow delete: if false;
```

Direct group document deletion is forbidden. The `deleteGroup` callable recomputes net
balances across all events plus group settlements, refuses non-zero net, then
soft-deletes the group and its events while keeping append-only expense and
settlement records reachable.

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

`allow create: if validExpenseCreate() || validEventSettlementCreate();`

Each branch enforces the module name plus its own schema.

**Expenses** (`validExpenseBase` + `validExpenseCreate`):

- Exact key set: `id, eventId, createdBy, payerParticipantId, amountFils, currency, description, scope, subGroupId, customSplitParticipants, splitMode, splitDistribution, receiptUrl, categoryId, note, isDeleted, deletedAt, createdAt, lastEditedBy, splitExplanation`
- `id == {docId}`, `eventId == {eid}`
- `payerParticipantId in event.participantIds`
- `amountFils` is a positive int (money is stored as subunits — see [ARCHITECTURE.md § Financial Calculations](./ARCHITECTURE.md))
- `currency` passes the supported-code `validCurrency` allowlist
- `scope in ['global', 'sub_group', 'personal', 'custom']`
- `customSplitParticipants` is a list whose elements are all event participants
- `splitMode in ['equally', 'shares', 'exact', 'percent']` (if present)
- Optional string fields: `subGroupId`, `description`, `note`, `receiptUrl`, `categoryId`
- `isDeleted: false`, `deletedAt: null` at create
- `createdBy == request.auth.uid` and caller `isGroupMember` + `isEventParticipant` (#1131)

**Event settlements** (`validEventSettlementBase` + `validEventSettlementCreate`):

- Exact key set: `id, eventId, createdBy, payerParticipantId, recipientParticipantId, amountFils, currency, note, payerName, recipientName, isDeleted, deletedAt, settledAt`
- Payer and recipient must both be participants AND different from each other
- `payerName` / `recipientName` are nullable valid display names
- `amountFils` positive int, `currency` passes the supported-code `validCurrency` allowlist
- `createdBy == request.auth.uid` and caller `isGroupMember`; the caller need not be an event participant (#752)

**Activity logs**:

- Clients may read event activity logs, but cannot create/update/delete them.
- Expense create/edit/soft-delete audit entries are written by the
  `expenseAuditLogger` trigger through the Admin SDK, bypassing rules.

#### Update

Only expenses are updatable (`validExpenseUpdate`):

- Caller is a current group member AND an event participant (#1131); creator-only edit was removed in #248 PR4
- `createdBy` cannot change
- `lastEditedBy == request.auth.uid` on every update for audit attribution
- Affected keys ⊆ `{payerParticipantId, amountFils, currency, description, scope, subGroupId, customSplitParticipants, splitMode, splitDistribution, receiptUrl, categoryId, note, isDeleted, deletedAt, lastEditedBy, splitExplanation}`
- The full base validator runs against the new state
- The `isDeleted` / `deletedAt` pair must either both stay the same OR perform the one-way soft-delete

#### Delete

```
allow delete: if false;
```

Direct document deletion is forbidden; use the soft-delete update path.

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
| `delete` (`validMemberDelete`) | Residual cleanup only after a server-authoritative membership mutation has already made the target absent from `group.memberIds` (or the group will not exist after the write). Self cleanup requires `resource.data.userId == request.auth.uid`; creator cleanup requires caller is `group.createdBy`. |

The cross-doc `getAfter` checks are a guardrail for batches that already
have a valid parent-group post-state: the member doc can be deleted only
when `groupAfter.memberIds` no longer contains that `userId` (or, for
creator cleanup, the group is absent after the write). Client group
updates no longer allow arbitrary `memberIds` removal, so direct
self-leave / creator-remove is not achieved through rules; use the
server callables (`leaveGroup`, `removeMember`, `deleteGroup`) for those
flows.

### 4.9 `groups/{gid}/activity/{activityId}` (group-level)

```
allow read: if isGroupMember(gid);
allow create: if validGroupActivityCreate();  // actor must be self
allow update, delete: if false;
```

Append-only audit log for group-scoped events (member joined, group
renamed, etc.). `validGroupActivityCreate` enforces the exact key set
and `actorId == request.auth.uid`.

Client-writable `type` allow-list (5 entries): `event_created`,
`event_deleted`, `event_settlement` (#831 — written by the event
settle-up record path; corrections and #752 decomposed settle-up slices
deliberately log nothing), `group_settlement`, `member_joined`.
`expense_*` and `member_left` are Admin-SDK-only (fan-in trigger /
callables) — a client claiming them is a forgery. The
`writeRateMonitor` skip list covers only the server-written `expense_*`
types; client-written types (both settlement flavors included) are
counted as real client writes.

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
the check instead. For what the `deleteAccount` callable may and may not
rewrite once it bypasses the rules, see
[Identity rewrites vs. financial immutability](#identity-rewrites-vs-financial-immutability-admin-sdk-maintenance) in §3.

| Concern | Why not in rules | Carried by |
|---------|------------------|------------|
| Invite-code redemption | A rule cannot atomically read `inviteCodes` + add to `memberIds` + fan out into all events while staying under the `get` budget. | `joinGroupByInviteCode` callable. |
| Rate-limiting failed joins | Rules cannot increment a counter across requests. | `joinAttempts` doc, written by the callable. |
| Account deletion cascade | Cross-collection scrub across hundreds of docs exceeds rules' write surface. | `deleteAccount` callable. |
| Currency whitelist | Rules enforce the same supported-code allowlist shape as the app; no FX, sign/sum, or cross-currency arithmetic is enforced in rules. | `validCurrency` + client `MoneySerializer` / balance tests. |
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
