# 50-Member Cap on joinGroupByInviteCode (#1282) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enforce the existing 50-member roster bound on invite-code joins, not only shadow-member creation, without burning the join rate limit for legitimate users of a full group.

**Architecture:** Hoist `MAX_GROUP_MEMBERS` into a shared module; enforce inside the join transaction gated on `didJoin` (idempotent re-joins and both heal paths stay unblocked at cap); tag the error with `details.reason = 'group-full'` and exempt that tag from `isLookupFailure` so a full group never counts toward the 5/hr throttle (the #279 collision precedent, achieved there via `already-exists`). Client maps the message to a specific l10n string via the established `_errorMessage` string-contains pattern.

**Tech Stack:** TypeScript Cloud Functions (Node 22), jest + Firebase emulator (`npm run test:emulator` — NEVER bare `npm test`, #1157), Flutter client l10n.

**Spec:** this document. **Issue:** #1282. **Deploy:** backend delta rides the v1.9.3 deploy ceremony (no rules change; old clients see a clean callable error — no PERMISSION_DENIED class risk).

---

## Verified current state (all re-read 2026-07-17 on main @ 97301000)

- `functions/src/callables/addShadowMember.ts`: `const MAX_GROUP_MEMBERS = 50` (:29) with comment (:25-28) ending "This caps ONLY the shadow-add path — joinGroupByInviteCode stays uncapped." Enforced at :103 as `memberIds.length >= MAX_GROUP_MEMBERS` → `failed-precondition` "This group has reached the maximum number of members."
- `functions/src/callables/joinGroupByInviteCode.ts`: no roster-size check (grep `MAX_GROUP_MEMBERS|memberIds.length` → zero hits). Structure inside the tx: quiesce-flag rejects (:251-261) → members+events snapshots (:266-269) → `MAX_FAN_IN_EVENTS` guard (:270-275) → `memberIds = getMemberIds(groupData)` (:276) → `hasMemberDocForUid` field-match (:286-288) → `didJoin = !hasMemberDocForUid && !memberIds.includes(uid)` (:301) → #279 collision check gated on `didJoin` (:320-334) → fan-in + writes.
- `isLookupFailure` (:122-125): `code === 'not-found' || code === 'failed-precondition'` → counted toward `recordFailedJoinAttempt` (5/hr, 1h lock). A naive `failed-precondition` group-full throw would lock a legit user out of ALL joins for an hour after 5 taps on a full group's valid link. (#279 dodged this by using `already-exists`; the existing `MAX_FAN_IN_EVENTS` `failed-precondition` DOES burn the throttle — pre-existing, out of scope here.)
- Client: `lib/features/groups/screens/join_group_screen.dart` `_errorMessage(String error)` (:325+) is a string-contains mapper over server messages → l10n keys (`Invalid invite code`, `already taken in this group`, `Too many attempts`, …). Server messages DO surface through it.
- Cap semantics on the shadow path: raw `memberIds.length`, which includes unclaimed-shadow uuids AND deleteAccount tombstone ids. The join cap uses the SAME basis — one contract, no drift between the two paths.

## Decisions (rationale the reviewers should attack)

1. **Gate on `didJoin`.** Only a genuinely-new member grows the roster. At cap, these still succeed: idempotent re-join (member doc + memberIds both present), the #53 heal (uid in memberIds, member doc missing — creates a doc, doesn't grow memberIds), the #1212 legacy uuid-keyed re-entry, and the inverse heal (`hasMemberDocForUid` true, uid missing from memberIds — the arrayUnion is a heal; since `didJoin` is false, it proceeds). Blocking heals would strand existing members of legacy over-50 groups.
2. **Check placement: immediately after `didJoin` is computed (:301-303), BEFORE the #279 collision check.** A full group should say "full", not "name taken"; and the collision scan over 50 docs is wasted work when full.
3. **Same error code + message as addShadowMember** (`failed-precondition`, "This group has reached the maximum number of members.") **plus `details: { reason: 'group-full' }`** — client-visible consistency, and the details tag is the throttle exemption hook.
4. **Throttle exemption via the details tag, not a message match.** `isLookupFailure` gains: an `HttpsError` whose `details.reason === 'group-full'` returns `false`. Rationale: a full group is a legitimate user outcome, not enumeration signal (a full group implies a VALID code). Do NOT switch the code to `already-exists` (semantically wrong, and addShadowMember consistency wins).
5. **addShadowMember imports the shared constant; its behavior is byte-identical.** Its :25-28 comment is REWRITTEN (the "caps ONLY the shadow-add path" sentence is now false) — the abuse-posture rationale moves to the shared module.
6. **No firestore.rules change.** Joins are Admin SDK writes via the callable; the rules never gated roster size.
7. **Claim-at-cap residual, accepted:** a new joiner who intends to claim an unclaimed shadow must join first, so at exactly 50 they're blocked and the claim offer is unreachable. Persona makes this vanishing (50 is far above any real group); the creator-side remedies (remove a member) exist. Documented, not engineered around.

## Data contracts (exact)

- New: `functions/src/callables/shared/groupLimits.ts`
  ```ts
  // Generous cap: bounds roster spam + per-write recompute cost. The persona
  // is small friend groups; 50 is far above any real Rihla group. Enforced on
  // BOTH roster-growth paths (addShadowMember, joinGroupByInviteCode) against
  // raw memberIds.length — which counts unclaimed shadows and deleteAccount
  // tombstones; one basis, no drift (#1282).
  export const MAX_GROUP_MEMBERS = 50;
  ```
- `joinGroupByInviteCode.ts`, after :303 (`groupName = …`):
  ```ts
  // #1282: cap genuinely-new joins only — didJoin=false re-joins and the
  // #53/#1212 heal paths must pass at cap (they don't grow the roster).
  // details.reason exempts this from the join throttle in isLookupFailure:
  // a full group implies a VALID code — user outcome, not enumeration.
  if (didJoin && memberIds.length >= MAX_GROUP_MEMBERS) {
    throw new HttpsError(
      'failed-precondition',
      'This group has reached the maximum number of members.',
      { reason: 'group-full' },
    );
  }
  ```
- `isLookupFailure` becomes:
  ```ts
  function isLookupFailure(error: unknown): boolean {
    const details = (error as { details?: unknown }).details;
    if (
      details && typeof details === 'object'
      && (details as { reason?: unknown }).reason === 'group-full'
    ) {
      return false;
    }
    const code = (error as { code?: unknown }).code;
    return code === 'not-found' || code === 'failed-precondition';
  }
  ```
- Client `_errorMessage`: add `if (error.contains('maximum number of members')) { return context.l10n.groupJoinGroupFull; }` before the generic fallback.
- New l10n key both arbs: `groupJoinGroupFull` — EN `"This group is full — it has reached the 50-member limit."`, AR `"هذه المجموعة ممتلئة — وصلت إلى الحد الأقصى (٥٠ عضوًا)."`

## Tasks

### Task 1: Emulator RED tests

**Files:** Modify `functions/test/callables/joinGroupByInviteCode.test.ts` (follow its existing fixtures/`clearFirestore` conventions; literal ids are shared across files — one jest runtime per emulator, use the runner).

Add a `describe('#1282 member cap')`:
- (a) group with 50 memberIds (padded synthetic ids) → new-uid join → rejects `failed-precondition`, message contains "maximum number of members", `details.reason === 'group-full'`; AND `joinAttempts/{uid}` has no `failCount` after the rejection (throttle not burned).
- (b) group with 49 → join succeeds (50th member lands).
- (c) at 50: existing member idempotent re-join → succeeds.
- (d) at 50: heal path (uid in memberIds, member doc deleted) → succeeds, member doc recreated.

**Step 2:** Run: `cd functions && npm run test:emulator -- test/callables/joinGroupByInviteCode.test.ts -t "member cap"` — (a)'s rejection and throttle assertions FAIL (join currently succeeds at 50). Paste output.

### Task 2: Server implementation

**Files:** Create `functions/src/callables/shared/groupLimits.ts`; modify `joinGroupByInviteCode.ts` (+import), `addShadowMember.ts` (import shared, delete local const, rewrite the :25-28 comment).

**Step 2:** Re-run Task 1 file — GREEN. Then the sibling: `npm run test:emulator -- test/callables/addShadowMember.test.ts` — green, byte-identical behavior.

**Step 3:** Commit `feat(functions): enforce the 50-member cap on invite-code joins` (body: `Refs #1282`).

### Task 3: Client mapping

**Files:** Modify `lib/features/groups/screens/join_group_screen.dart` (`_errorMessage`), `lib/l10n/app_en.arb` + `app_ar.arb` (`groupJoinGroupFull`); test: extend the existing join-screen test file with a case asserting the specific copy renders when the service throws the group-full message.

RED → implement → GREEN → `flutter analyze` → commit `feat(join): surface a specific group-full message` (body: `Closes #1282`).

### Task 4: Full verification

`cd functions && npm run lint && npm run test:emulator` (full suite, runner-allocated ports); `flutter test test/features/groups/`; `flutter analyze`.

## Out of scope (explicit)

- The `MAX_FAN_IN_EVENTS` throw's throttle burn (pre-existing; different bound).
- Any cap on event `participantIds` or claim-chain callables.
- Rules changes; client-side pre-flight roster counting (server is the boundary).
