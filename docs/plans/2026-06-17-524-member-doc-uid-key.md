# #524 — Bound member-doc creation to one-per-uid (id == auth.uid)

**Issue:** #524 — a signed-in group member can forge unlimited duplicate member docs for their own uid (client-chosen doc id, no uniqueness/existence check). Roster/identity pollution + extra `balanceAggregator` invocations + strains 1:1 `userId`-matching in `deleteAccount`/`removeMember`. Balance is safe (`recomputeNet` Set-dedupes by `userId`). P3, integrity/abuse.

**Gate category:** `security/firestore.rules` change. Mandatory fresh-context Gate before implementation.

## Root cause (verified against live code)

`validMemberCreate` (`security/firestore.rules:764-783`) gates a member-doc create on:
- `isGroupMember(groupId)` (caller in `memberIds`),
- `request.resource.data.id == memberId` (the client-chosen path segment),
- `request.resource.data.userId == request.auth.uid`,
- shape/displayName/role/timestamp checks.

It **never** binds the doc id to the uid, so an existing member can `set` arbitrarily many docs each under a fresh random `memberId`, all with their own `userId`. Firestore rules cannot run a collection query, so "is a member doc with `userId==uid` already present?" is unexpressible; `!exists(members/$(memberId))` is useless here because the forger uses a fresh id each time. The only rule-expressible uniqueness is a **deterministic doc path** = uid.

## The only client-side member-doc CREATE (verified, exhaustive sweep)

`grep "collection('members')"` across `lib/`:
- `group_provider.dart:165` `final memberId = uuid.v4()` → `:203 .set(...)` — **createGroup creator self-add** (the one create).
- `group_provider.dart:360` `updateMemberDisplayName` — `.update` (not create).
- `group_provider.dart:447` `watchMembers` — read.
- `settings_provider.dart:152` `_ensureDisplayNameAvailable` — `.get` (read).
- `settings_provider.dart:197` `propagateDisplayName` — `batch.update(... by userId field)` (not create).

Joiners are created **server-side** by `joinGroupByInviteCode.ts:290` `groupRef.collection('members').doc(uid)` — already **uid-keyed**, and Admin SDK bypasses rules (rule change does not touch the join path). So today the creator doc is the lone uuid-keyed member doc (the CLAUDE.md "member doc keying is INCONSISTENT" bear trap); joiners + recovery-copies already key by `{uid}`.

## Fix (rule + client, both required)

1. **Rule** (`security/firestore.rules`, `validMemberCreate`): add
   `&& request.resource.data.id == request.auth.uid`.
   Combined with the existing `id == memberId`, this forces `memberId == uid`, so the create path is the single deterministic doc `members/{uid}`. `allow create` fires only when that doc is absent → exactly one client-created member doc per uid. A forged `members/{random}` write now fails (`random != uid`).

2. **Client** (`group_provider.dart`): key the creator's member doc by `uid` instead of `uuid.v4()`. Change `final memberId = uuid.v4();` (line 165) so the creator doc is written at `.doc(uid)` with `id: uid`. This aligns the creator with joiners (uid-keyed) and resolves the inconsistency bear trap for **new** groups.

## Why this is safe

- **No migration / no real users.** Rules gate only new writes. Legacy prod creator docs (uuid-keyed) remain valid: their updates go through `validSelfDisplayNameUpdate` (matches by `userId` field, id-agnostic), deletes are server-only (#190/#290). #294 already made every server cascade match by the `userId` field, so doc-id keying is not load-bearing anywhere. (And per project state there are no real users yet.)
- **`memberId` is not referenced after creation** in `stageGroup` (uuid was a throwaway, used only at `.doc(memberId)` / `'id': memberId`). Keying by uid changes only the doc path.
- **Recovery is trivially safe — there is no member-doc copy/migration at all.** The cross-UID merge engine (`cleanupAnonUidArtifacts`) was DELETED in #441 (PR4/PR5, `c009b700`); recovery is now in-place credential linking (uid unchanged) or a sign-in swap to an already-owned durable uid (`auth_recovery_service.dart`). So a uid-keyed creator doc has nothing to collide with.
- **Group-create chained-ack pattern unchanged** (member write still chained on `batch.commit()` ack; only the doc id differs). The create now lives in `stageGroup` (#520 offline-staging refactor), not a separate `createGroup` body.

## Tests (RED→GREEN)

**Rules (`functions/test/firestore-rules-publish-readiness.test.ts`, emulator):**
- NEW: an existing member (`member`, in `memberIds`, already has `members/member`) creating an EXTRA doc `members/forged-1` with `userId:'member'` → **assertFails** (RED today: succeeds; GREEN: `id 'forged-1' != uid 'member'`).
- NEW/guard: a uid in `memberIds` with NO existing member doc creating `members/{uid}` (id==uid) → **assertSucceeds** (the legit createGroup creator path; passes before and after).
- Existing `eve` non-member test and `members can update only their own display name` test must stay green.

**Dart (`group_provider` test):**
- createGroup writes the creator member doc at `members/{uid}` with `id == uid` (assert the doc id, not a uuid). Find/extend the existing createGroup test; add if absent.

## Out of scope

- Bounding legacy duplicates already in prod (none expected; no real users). No backfill.
- #278 shadow-member creation (unbuilt; no create path exists to constrain).

## Sequence

spec → **Gate** → rules emulator RED → client Dart RED → implement rule + client → GREEN → `flutter analyze` + Dart tests + scoped emulator test → `/automerge` (Gate-category: review+refute) → **deploy ceremony** (rules deploy) → record ledger.
