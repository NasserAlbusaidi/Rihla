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

Even though the polymorphic `{module}` rule above already disallows
updates and deletes for settlements (no `validSettlementUpdate`
exists), the rules add an explicit match to make B3 visible:

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
the check instead.

| Concern | Why not in rules | Carried by |
|---------|------------------|------------|
| Invite-code redemption | A rule cannot atomically read `inviteCodes` + add to `memberIds` + fan out into all events while staying under the `get` budget. | `joinGroupByInviteCode` callable. |
| Rate-limiting failed joins | Rules cannot increment a counter across requests. | `joinAttempts` doc, written by the callable. |
| Account deletion cascade | Cross-collection scrub across hundreds of docs exceeds rules' write surface. | `deleteAccount` callable. |
| UID migration after recovery | Same. | `cleanupAnonUidArtifacts` callable. |
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
RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes \
  bash tool/deploy_firebase_backend.sh rihla-safar
```

The script also diffs current production rules against the repo first
and refuses to deploy a regression without confirmation. See
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
