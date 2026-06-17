# Shadow Members — Add-by-Name (Minimal slice of #278) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let a group creator add placeholder ("shadow") members **by name** so a brand-new group is usable on the first session — shadows appear in the roster, are split against, can pay, and can be cash-settled — without anyone else installing the app first.

**Architecture:** A shadow MUST live in `groups/{gid}.memberIds` to participate (event expenses gate `participantIds ⊆ memberIds`, `firestore.rules:367`), and `memberIds` is fully server-authoritative (`:308`, #524 `:782-783`). So shadow creation is a **new Admin-SDK callable `addShadowMember`** that mints a placeholder uuid, writes a `members/{uuid}` doc with `isShadow:true`, and `arrayUnion`s the uuid into `memberIds`. The balance oracle is identity-blind (0 `isShadow` in `groupNetBalance.ts`/`expense_provider.dart`), so a uuid is just another member id — **no rules change, no oracle change**. Removal of a mistyped (zero-balance) shadow reuses the existing identity-blind `removeMember` callable. Client UI seeds names at create + in-group and renders the shadow state.

**Tech Stack:** Cloud Functions (Node 22 / TypeScript, `firebase-functions/v2`), Firestore Admin SDK, Jest + Firestore emulator (Java 21); Flutter / Riverpod / Dart client.

**Scope guard (v1 judgment calls):**
- **Creator-only** add (aligns with `removeMember`'s creator gate + the "one person logs for the group" persona). Any member may still split against an existing shadow.
- Add at **create time AND in-group**.
- Event fan-out is **opt-in per event** via the existing participant picker (no retroactive auto-add to past events).
- **Claim/merge-on-join is OUT of this slice** — separate plan, gated on owner decisions D1–D6 (see `docs/research/2026-06-17-278-shadow-members-investigation.md`).

**This slice is Gate-category** (new Cloud Function with auth/validation + money-adjacent). PR1 must clear `/run-the-gate` before code; its money/parity tests are non-negotiable.

---

## Reference reading (the engineer has zero context)

- Callable template to mirror: `functions/src/callables/joinGroupByInviteCode.ts` (anon-reject `:236`, `normalizeDisplayName` `:70-87`, #279 collision check `:330-344`, member-doc write `:375-384`, `arrayUnion` into memberIds `:368-373`).
- Reuse-for-removal: `functions/src/callables/removeMember.ts` (identity-blind `targetUserId`, match `where('userId','==',…)` `:107`, creator gate `:90`, per-currency net==0 `:131`).
- Test harness to mirror: `functions/test/callables/removeMember.test.ts` (`functionsTest({projectId})`, `testEnv.wrap`, `clearFirestore`, `seedGroup/seedMember/seedEvent/seedExpense/seedEventSettlement`).
- Export drift trap: `functions/src/index.ts` re-exports + `tool/list_expected_functions.sh` (awk). A new function MUST be a `export { addShadowMember } from …` re-export, never a bare `export const` (invisible to the deploy-drift extractor — CLAUDE.md landmine).
- Emulator-test landmine: `npm run test:emulator -- <file>` SILENTLY runs the FULL suite. To scope: `RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/addShadowMember.test.ts" npm run test:emulator` (run from `functions/`).
- Rules facts: `firestore.rules:367` (participantIds⊆memberIds), `:477/:548/:554` (split/payer/customSplit ⊆ participants), `:764-790` `validMemberCreate` (Admin SDK bypasses), `:801-818` `validMemberDelete`.

---

## PR1 — `addShadowMember` callable (BACKEND, **GATE**)

**Files:**
- Create: `functions/src/callables/shared/displayName.ts`
- Create: `functions/src/callables/addShadowMember.ts`
- Modify: `functions/src/index.ts` (add the re-export, alphabetical with the other callables)
- Create: `functions/test/callables/addShadowMember.test.ts`

### Task 1.1 — Extract the shared display-name normalizer (no behavior change)

`normalizeDisplayName` is currently file-private in `joinGroupByInviteCode.ts:70-87`. The new callable needs the SAME validation. To avoid touching the sensitive join callable in this PR, create a NEW shared module used only by `addShadowMember`; leave `joinGroupByInviteCode` untouched (a later trivial refactor can de-dup). **Temporary duplication is intentional and noted.**

**Step 1:** Create `functions/src/callables/shared/displayName.ts`:

```typescript
import { HttpsError } from 'firebase-functions/v2/https';

const DISPLAY_NAME_MAX_LENGTH = 32;
// Matches control characters to REJECT them — server counterpart to
// isValidDisplayName, kept aligned with firestore.rules. (Mirror of the
// joinGroupByInviteCode validator; de-dup is a tracked follow-up.)
// eslint-disable-next-line no-control-regex
const CONTROL_CHARACTER_PATTERN = /[\x00-\x1F\x7F]/u;
// firestore.rules:50 isValidDisplayName ALSO rejects a name ending in
// " (former member)" — and the SAME suffix is rejected per-value in
// displayNameMapValuesAreValid (rules:65), which validEventBase enforces on
// participantNames (rules:369). A shadow's name is COPIED into an event's
// participantNames when the creator adds the shadow to an event, so a shadow
// named "Bob (former member)" would persist via Admin SDK but then make the
// CLIENT event-create/update fail PERMISSION_DENIED. Reject it up front here.
const FORMER_MEMBER_SUFFIX_PATTERN = / \(former member\)$/u;

/// Validate a REQUIRED display name, mirroring firestore.rules:44-51
/// isValidDisplayName (1–32 chars, no control chars, no "(former member)"
/// suffix). Unlike joinGroupByInviteCode's normalizeDisplayName, a missing name
/// is an ERROR (a nameless shadow is meaningless) — no 'Anonymous' default.
export function normalizeRequiredDisplayName(value: unknown): string {
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', 'displayName must be a string.');
  }
  const trimmed = value.trim();
  if (trimmed.length < 1 || trimmed.length > DISPLAY_NAME_MAX_LENGTH) {
    throw new HttpsError(
      'invalid-argument',
      `displayName must be between 1 and ${DISPLAY_NAME_MAX_LENGTH} characters.`,
    );
  }
  if (CONTROL_CHARACTER_PATTERN.test(value)) {
    throw new HttpsError('invalid-argument', 'displayName contains invalid characters.');
  }
  if (FORMER_MEMBER_SUFFIX_PATTERN.test(trimmed)) {
    throw new HttpsError('invalid-argument', 'displayName is not allowed.');
  }
  return trimmed;
}
```

> Add a test case to PR1 Task 1.2 (test 4 table): `displayName: "Bob (former member)"` → `invalid-argument` (would otherwise break client event-create when the shadow is added to an event).

**Step 2:** Commit — `git commit -m "feat(functions): shared required-display-name normalizer for shadow add"`

### Task 1.2 — RED: write the failing callable test suite

**Step 1:** Create `functions/test/callables/addShadowMember.test.ts`. Mirror `removeMember.test.ts` setup (functionsTest, wrap, clearFirestore, logger spies, `seedGroup`/`seedMember`/`seedEvent`/`seedExpense`). `OWNER` is creator; a second uid `OUTSIDER` is a non-creator member.

Tests (each asserts code + that NO unintended writes happened):

```
1.  missing auth → unauthenticated
2.  anonymous caller (token.firebase.sign_in_provider==='anonymous') → permission-denied; memberIds unchanged
3.  invalid groupId ("" and "a/b") → invalid-argument
4.  missing/blank/too-long/control-char displayName → invalid-argument (table: null, "", "  ", 33 chars, "ab")
5.  missing group → not-found
6.  soft-deleted OR deletingInProgress group → not-found; no member doc created
7.  non-creator member caller → permission-denied; memberIds unchanged, no new member doc
8.  HAPPY: creator adds "Sara" → returns {memberId}; members/{memberId} has {userId===memberId, displayName:'Sara', role:'MEMBER', isShadow:true}; memberId ∈ group.memberIds; memberIds length grew by exactly 1
9.  name collision (case-insensitive, trimmed) with an existing REAL member → already-exists; no write
10. name collision with an existing SHADOW → already-exists; no write
11. two distinct names → two shadow docs, both in memberIds, distinct uuids
12. member cap: seed memberIds at MAX_GROUP_MEMBERS → failed-precondition; no write
13a. PARITY / shadow-as-DEBTOR: creator adds shadow "Sara"; seed an event participantIds=[OWNER, sara] + an expense OWNER pays 12.000 OMR split equally → groupNetBalance oracle nets sara −6.000, OWNER +6.000 (shadow IS counted, not dropped from the universe)
13b. PARITY / shadow-as-PAYER ("Sara paid the taxi"): expense payerParticipantId=sara, 12.000 OMR split equally over [OWNER,sara] → oracle nets sara +6.000, OWNER −6.000 (a shadow uuid is a legal payer because it's in memberIds⊇participantIds)
13c. PARITY / shadow CASH-SETTLED: 13a state + an event settlement OWNER←sara 6.000 OMR → oracle nets sara 0.000 (a shadow can be a settlement party)
14. PARITY/REMOVAL: a non-zero shadow (13a state) → removeMember(targetUserId=sara) rejects failed-precondition (doc + memberIds untouched); a brand-new zero-balance shadow → removeMember removes it (memberIds loses the uuid, doc deleted) — confirms the reuse claim
```

**Step 2:** Run RED — expect "Cannot find module '../../src/callables/addShadowMember'":

`cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/addShadowMember.test.ts" npm run test:emulator`

Expected: FAIL (module not found / suite errors).

**Step 3:** Commit the RED test — `git commit -m "test(functions): RED addShadowMember callable + shadow balance parity"`

### Task 1.3 — GREEN: implement the callable

**Step 1:** Create `functions/src/callables/addShadowMember.ts`:

```typescript
import { getFirestore, FieldValue, DocumentData } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { randomUUID } from 'crypto';
import '../admin';
import { normalizeRequiredDisplayName } from './shared/displayName';

export interface AddShadowMemberInput {
  groupId: string;
  displayName: string;
}
export interface AddShadowMemberOutput {
  memberId: string;
}

// Generous cap: bounds roster spam + recompute cost. The persona is small
// friend groups; 50 is far above any real Rihla group. App Check + creator-only
// are the real controls (#197 — do NOT add per-IP throttling).
const MAX_GROUP_MEMBERS = 50;

function normalizeGroupId(groupId: unknown): string {
  if (typeof groupId !== 'string' || groupId.length === 0 || groupId.includes('/')) {
    throw new HttpsError('invalid-argument', 'groupId must be a valid id.');
  }
  return groupId;
}

function getMemberIds(groupData: DocumentData): string[] {
  const memberIds = groupData.memberIds;
  if (!Array.isArray(memberIds) || memberIds.some((m) => typeof m !== 'string')) {
    throw new HttpsError('failed-precondition', 'Group membership data is malformed.');
  }
  return memberIds;
}

export const addShadowMember = onCall<AddShadowMemberInput, Promise<AddShadowMemberOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<AddShadowMemberInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    // A shadow is group-scoped placeholder data; the CREATOR adds it and is
    // always durable (validGroupCreate requires a durable sign-in). Reject anon
    // defensively, mirroring joinGroupByInviteCode:236.
    if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError(
        'permission-denied',
        'A linked (non-anonymous) account is required to add members.',
      );
    }

    const uid = request.auth.uid;
    const groupId = normalizeGroupId(request.data?.groupId);
    const displayName = normalizeRequiredDisplayName(request.data?.displayName);
    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);

    const memberId = await db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      if (!groupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const groupData = groupSnap.data() ?? {};
      // Honor the same write-lock as firestore.rules (Admin SDK bypasses rules).
      if (groupData.isDeleted === true || groupData.deletingInProgress === true) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      if (groupData.createdBy !== uid) {
        throw new HttpsError(
          'permission-denied',
          'Only the group creator can add members by name.',
        );
      }
      const memberIds = getMemberIds(groupData);
      if (memberIds.length >= MAX_GROUP_MEMBERS) {
        throw new HttpsError(
          'failed-precondition',
          'This group has reached the maximum number of members.',
        );
      }

      const membersSnap = await tx.get(groupRef.collection('members'));
      // #279 collision: a shadow name must be unique (case-insensitive, trimmed)
      // across ALL member docs (real + shadow) — duplicate names make roster +
      // settle-up attribution ambiguous, and keeping names unique now keeps the
      // future claim picker unambiguous. Compared by the displayName FIELD.
      const candidate = displayName.toLowerCase();
      const collides = membersSnap.docs.some((d) => {
        const existing = d.get('displayName');
        return typeof existing === 'string' && existing.trim().toLowerCase() === candidate;
      });
      if (collides) {
        throw new HttpsError(
          'already-exists',
          'That name is already taken in this group. Please choose a different name.',
        );
      }

      // Placeholder uuid is BOTH the doc id and the userId (the balance oracle
      // keys on userId). Same 6 fields joinGroupByInviteCode writes, isShadow:true.
      const newId = randomUUID();
      tx.set(groupRef.collection('members').doc(newId), {
        id: newId,
        userId: newId,
        displayName,
        role: 'MEMBER',
        joinedAt: FieldValue.serverTimestamp(),
        isShadow: true,
      });
      tx.update(groupRef, {
        memberIds: FieldValue.arrayUnion(newId),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return newId;
    });

    logger.info('addShadowMember created', { uid, groupId, memberId });
    return { memberId };
  },
);
```

**Step 2:** Add the re-export to `functions/src/index.ts` (keep it a `export { … } from` line so `list_expected_functions.sh` sees it):

```typescript
export { addShadowMember } from './callables/addShadowMember';
```

**Step 3:** Run GREEN — same scoped command as Task 1.2 Step 2. Expected: all PR1 tests PASS.

**Step 4:** `cd functions && npm run build` (tsc) clean; `npm run lint` clean.

**Step 5:** Commit — `git commit -m "feat(functions): addShadowMember callable — creator adds placeholder members by name (#278)"`

### Task 1.4 — Deploy-drift + readiness

**Step 1:** `bash tool/list_expected_functions.sh` includes `addShadowMember`. Run `flutter test test/unit/release_workflow_gate_test.dart` (the deploy-drift gate) — green.

**Step 2:** Backend deploy is a SEPARATE ceremony after merge (`deploy-ceremony` skill / `tool/pending_deploy.sh`). No real users → deploy freely. Note in the PR body that PR1 needs a backend deploy before the client PRs are testable on-device.

---

## PR2 — Add-by-name chips at group create (CLIENT, Gate-exempt)

**Files:**
- Modify: `lib/features/groups/screens/create_group_screen.dart`
- Modify: `lib/features/groups/providers/group_provider.dart` (add a `addShadowMember` callable wrapper if no callable service exists)
- Modify/Create: l10n keys in `lib/l10n/app_en.arb` + `app_ar.arb` (`createGroupWhoElse`, `createGroupAddNameHint`, `createGroupShadowHint`, `shadowMemberBadge`)
- Test: `test/features/groups/create_group_shadow_members_test.dart`

**Behavior:** Below "Your name", a "Who's in?" chips field (mockup V1). Type a name → a dashed shadow chip (with ×). On Create: `stageGroup` (creator doc, offline-capable) → await its ack → then call `addShadowMember(groupId, name)` per chip. **Callables need connectivity** — if offline, disable the chips field with a "needs connection to add names" hint; the group still creates with just the creator (no half-state beyond the creator doc). Collision / errors surface per-chip (snackbar with `persist:false`).

**Tasks (TDD):**
1. RED widget test: enter group name + 2 chips, tap Create online → asserts `addShadowMember` called twice with the two names (mock the callable wrapper). 
2. RED: offline (mock connectivity offline) → chips field disabled, Create still works with 0 shadow calls.
3. RED: `already-exists` from the callable → the offending chip shows an error state, group still created.
4. GREEN: implement the chips widget + wire to the wrapper.
5. Run `flutter analyze` clean (mark const literals; `prefer_const_constructors` fails CI); run the new test + `flutter test test/features/groups/`.
6. Commit — `feat(groups): add members by name at create via addShadowMember (#278)`.

> Verify during build: after create, the creator can make an event whose participant picker already lists the shadows (they are in `memberIds`), and an expense split includes them — that is the end-to-end Friday flow. If the event-participant picker or expense split excludes shadows, fold the fix into PR4.

---

## PR3 — In-group add-shadow + shadow badge + remove (CLIENT, Gate-exempt)

**Files:**
- Modify: `lib/features/groups/widgets/group_members_section.dart` (wire the dead `groupManage` header action → add-shadow sheet)
- Modify: `lib/features/groups/screens/group_settings_screen.dart`
- Test: `test/features/groups/group_members_section_shadow_test.dart`

**Behavior:** A "+ Add person" affordance (creator-only) opens a name sheet → `addShadowMember(groupId, name)`. Member tiles show a "Not joined yet" pill when `isShadow`. A zero-balance shadow tile offers Remove → `removeMember(targetUserId: shadow.userId)` (reuses the existing callable; non-zero → the callable's failed-precondition surfaces as "settle up first").

**Tasks (TDD):** RED tests for (a) creator sees Add person, non-creator does not; (b) shadow tile renders the pill; (c) tapping Add calls `addShadowMember`; (d) Remove on a zero-balance shadow calls `removeMember`. GREEN. analyze + tests. Commit.

---

## PR4 — Thread `isShadow` into ledger split/payer pickers (CLIENT, Gate-exempt)

**Files:**
- Modify: `lib/features/ledger/widgets/split_scope_selector.dart` (the existing `editorShadowProfile` label is **dead** — `_eventParticipants` builds `Participant` with `isShadow` defaulting `false` at `lib/features/trip/models/trip_model.dart:36`; thread `GroupMember.isShadow` by `userId` lookup so the subtitle renders)
- Modify: `lib/features/ledger/widgets/custom_split_sheet.dart` (add optional `isShadow` to `SplitParticipant`, set from the GroupMember lookup)
- Modify: `lib/features/events/widgets/event_participants_card.dart` (shadow pill + disambiguate duplicate-name display via the #196 resolver — this picker currently uses raw `displayName`)
- Test: extend ledger widget tests

**Behavior:** Pure display — shadows show a "Shadow / Not joined yet" marker in split, payer, custom-split, and event-participant pickers. No money-path change.

**Tasks (TDD):** RED test that a shadow participant in the custom-split sheet shows the shadow subtitle (currently dead). GREEN by threading the flag. analyze + ledger tests (`test/features/ledger/`, mind the `ledger_screen_overflow_test` horizontal-strip + `EmptyStateView` `pumpAndSettle` traps). Commit.

---

## Known limitation (ship-and-surface, not a bug)

Until the claim/merge slice ships, a **real friend cannot join under a shadow's name**: the #279 collision guard (`joinGroupByInviteCode.ts:330-344`) rejects a join whose name matches an existing member, and a shadow IS a member. So if the creator seeds shadow "Khalid" and real-Khalid later joins with the invite code typing "Khalid", he is rejected ("name already taken"). Workarounds for v1: real-Khalid joins under a slightly different name, or the creator removes the shadow first. This is exactly the friction the **claim/merge** slice removes (real-Khalid *adopts* the placeholder). For the Minimal Friday flow this never bites — the creator logs everything solo and nobody else needs to join. **Call this out in the PR body and the #278 re-scope so it reads as a known limitation, not a surprise.** (`MAX_GROUP_MEMBERS=50` is also shadow-add-only, not a group-wide cap — `joinGroupByInviteCode` stays uncapped.)

## Done-criteria for the add-by-name slice

- [ ] PR1 Gate-cleared (no [P1]) before code; money/parity tests green; `flutter analyze` + functions `build`/`lint` clean.
- [ ] PR1 merged + **backend deployed** (deploy-ceremony; `backend-deployed` tag advanced; `addShadowMember` in the prod function set).
- [ ] PR2 lets the creator seed names at create (online) and the full create→event→expense→balance flow works with shadows.
- [ ] PR3/PR4 polish (badges, in-group add, remove, shadow labels).
- [ ] CLAUDE.md "Name-based members" invariant updated: creator can now add shadow members by name; `isShadow` has a creation path; `removeMember` removes zero-balance shadows. Note claim/merge still unbuilt (separate plan).
- [ ] #278 stays OPEN, re-scoped to the claim/merge slice (`Refs #278` in PRs, not `Closes`).
```
