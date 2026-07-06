# Anon Shadow Sandbox (D6 revision) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let an anonymous first-session user experience the full core loop — add people by name, split, see balances, cash-settle — by moving the durable-credential boundary from "name a placeholder" to "decide a shadow claim".

**Architecture:** Remove the anon-reject from two creator-scoped callables (`addShadowMember` write, `listGroupClaimRequests` read); the durable boundary that matters — the CLAIM chain — is already enforced and does not change: `requestClaimShadow` (anon claimers rejected), `decideClaimRequest` (anon approvers rejected — the load-bearing gate this plan promotes to the product boundary). NOTE (merge-review correction): joining is anon-legal by design since #648 (`joinGroupByInviteCode.ts:184-187` — "NO anonymous-provider reject here… Do not re-add it"); the original draft wrongly named join as a durable gate. Client drops the `isDurableUserProvider` condition from the three add-by-name affordances and adds one new pre-gate: tapping Approve/Decline on a claim request as an anon creator opens the durable-credential sheet instead of calling the server.

**Tech Stack:** Flutter/Riverpod client, Firebase Cloud Functions (TS, Node 22), Jest + emulator, flutter_test.

---

## Decision record — D6-R (owner decision, 2026-07-06)

Supersedes D6 (`docs/plans/2026-06-17-278-claim-merge.md`) **in part**:

| | D6 (old) | D6-R (new) |
|---|---|---|
| Add shadow by name | durable creator only | **any creator, incl. anonymous** |
| List claim requests (creator) | durable only | **any creator, incl. anonymous** |
| Request a claim | durable only | durable only (unchanged) |
| Decide a claim | durable only | durable only (unchanged — now THE boundary; client pre-empts with link sheet) |
| Join by invite code | anon-legal (#648) | anon-legal (#648 — unchanged; the draft's "durable only" was wrong) |

**Why:** the durable gate on add-by-name blocked the exact user shadows were designed for (`addShadowMember.ts` header: *"a brand-new group is usable on the first session — split against it immediately, cash-settle it"*). A solo anon sandbox harms nobody if its creator evaporates — no other real identity is entangled. The moment that needs a durable identity is the **claim** (both sides already durable-gated); joins are anon-legal by design (#648). Linking keeps the UID, so a sandbox survives the upgrade with zero migration.

**Accepted residuals (2, both safe):**
1. An anon creator who gets real joiners and then evaporates leaves unclaimed shadows unclaimable (approval needs the creator). Worst case: the placeholder stays a placeholder; balances stay consistent; settle-on-behalf still works (`isGroupMember` settlement create, #752). Today that state is impossible only because the sandbox itself was impossible. The claim-request row doubles as the link nudge at exactly the moment it matters.
2. (Gate R1 adversary) An anon creator whose Google account is ALREADY bound to a different Firebase user hits `GoogleLinkConflictException` in the link sheet, and the "switch" offer is correctly blocked by `outgoingShellProvablyEmpty` (their group makes the shell non-empty, `durable_credential_sheet.dart:127-155,163-169`) — so THAT shell can never approve claims. Safe dead-end (no data loss, no swap); resolution is linking a different Google account. Known limitation — do not refile as a bug.

**Abuse posture unchanged:** `enforceAppCheck: true`, creator-only check (`addShadowMember.ts:86`), `MAX_GROUP_MEMBERS = 50` cap, `normalizeRequiredDisplayName` validation, event fan-in cap. No per-IP throttle (#197 stands). Anon group creation is already allowed (#818) — this extends the same posture one step, not a new class of actor.

## Verification principles (run while authoring — results)

1. **Callsite classification:** `addShadowMember` writes member docs via Admin SDK — OUTBOUND, **shape unchanged** (no field added/removed; only the caller-eligibility predicate relaxes). `listGroupClaimRequests` is INBOUND (display-only list). `claim_requests_section.dart` `_decide` is OUTBOUND via callable — unchanged payload, new client pre-gate only.
2. **Concrete claims verified against code:** anon rejects at `addShadowMember.ts:57`, `listGroupClaimRequests.ts:45`, `requestClaimShadow.ts:53`, `decideClaimRequest.ts:167`, creator checks at `addShadowMember.ts:86`, `listGroupClaimRequests.ts:61`, `decideClaimRequest.ts:196,220`; client gates at `create_group_screen.dart:364-395` (chips `enabled` + `disabledHint` + #840 CTA), `group_detail_screen.dart:159,265,272`, `group_members_section.dart:44-46,76-86`; `showDurableCredentialSheet` returns `Future<bool>` (`durable_credential_sheet.dart:30`), true only after link + token refresh.
3. **Read-path per write-path:** member docs → `watchMembers` (`group_provider.dart`) + oracle universe construction — both keying-agnostic (`userId` field match) and already handle shadows; nothing changes shape.
4. **Fields enumerated from type:** no model/schema change anywhere. No `**/models/**` file touched.
5. **Data contracts:** callable payloads unchanged byte-for-byte; only auth-predicate relaxation.
6. **Arithmetic decomposition:** N/A — no money math touched. `BalanceCalculator`/oracle/rules untouched.
7. **Orthogonal axes:** identity (anon non-creator still rejected by creator check — pinned by test), time (anon→linked keeps UID; sandbox survives), scope (join/claim gates unchanged — pinned by existing tests that must stay green), money-flow (settlement against a shadow already legal and untouched).

**Rules:** `security/firestore.rules` untouched — shadow member docs are Admin-SDK writes (bypass rules); group creation is already anon-legal on prod.

---

### Task 1: Server — `addShadowMember` accepts an anonymous creator

**Files:**
- Modify: `functions/src/callables/addShadowMember.ts:51-63` (delete the anon-reject block + rewrite comment)
- Test: `functions/test/callables/addShadowMember.test.ts:177` (flip test 2)

**Step 1: Flip test 2 to the new contract (RED)**

Replace test `'2. anonymous caller → permission-denied; memberIds unchanged'` with two tests:

```ts
test('2. anonymous CREATOR succeeds — shadow minted, memberIds appended (D6-R)', async () => {
  const res = await run(addShadowMember, {
    data: { groupId: GROUP, displayName: 'Alice' },
    auth: { uid: OWNER, token: { firebase: { sign_in_provider: 'anonymous' } } },
  });
  expect(res.memberId).toBeTruthy();
  const group = await db.doc(`groups/${GROUP}`).get();
  expect(group.data()!.memberIds).toContain(res.memberId);
  const member = await db.doc(`groups/${GROUP}/members/${res.memberId}`).get();
  expect(member.data()!.isShadow).toBe(true);
});

test('2b. anonymous NON-creator → permission-denied (creator check, not provider)', async () => {
  await expect(run(addShadowMember, {
    data: { groupId: GROUP, displayName: 'Alice' },
    auth: { uid: OUTSIDER, token: { firebase: { sign_in_provider: 'anonymous' } } }, // Gate R1: file defines OWNER/OUTSIDER, no JOINER
  })).rejects.toMatchObject({ code: 'permission-denied' });
  // memberIds unchanged
});
```

(Adapt `run(...)` harness + fixture names to the file's existing helpers — mirror test 1/3 setup exactly.)

**Step 2: Run to verify RED**

Run: `cd functions && bash ../tool/run_firebase_emulator_tests.sh callables/addShadowMember.test.ts -t "anonymous"`
Expected: test 2 FAILS (`permission-denied` thrown), 2b passes (creator check already rejects).

**Step 3: Remove the reject (GREEN)**

Delete `addShadowMember.ts` lines 51-63 (comment + `if (sign_in_provider === 'anonymous') throw`) and replace with:

```ts
    // D6-R (2026-07-06): anonymous creators MAY add shadows — the sandbox is
    // solo until a real account joins. Joining is itself anon-legal (#648 —
    // see joinGroupByInviteCode), so the durable boundary is the CLAIM chain:
    // requestClaimShadow / decideClaimRequest both reject anonymous actors.
    // Abuse posture: enforceAppCheck + creator-only check below + MAX_GROUP_MEMBERS.
```

**Step 4: Run to verify GREEN**

Run: same command. Expected: whole file PASS (including untouched tests 1/3+ — the creator-check and validation legs).

**Step 5: Commit**

```bash
git add functions/src/callables/addShadowMember.ts functions/test/callables/addShadowMember.test.ts
git commit -m "feat(groups): addShadowMember accepts anonymous creators (D6-R)"
```

### Task 2: Server — `listGroupClaimRequests` readable by an anonymous creator

**Files:**
- Modify: `functions/src/callables/listGroupClaimRequests.ts:45-49` (delete anon-reject)
- Test: `functions/test/callables/claimRequest.test.ts` (Gate R1: there is NO `listGroupClaimRequests.test.ts` — the list callable's tests live here, import at `:20`, list block near `:735`. The `:45` anon-reject is currently UNCOVERED, so removing it breaks no existing test — the anon-creator test must be **ADDED**, not flipped, or D6-R ships untested.)

**Steps (same RED→GREEN shape as Task 1):**
1. ADD two tests to `claimRequest.test.ts`'s list block: anon CREATOR lists pending requests successfully (RED against current code — expects success, gets `permission-denied`); anon NON-creator → `permission-denied` (creator check at `:61`).
2. RED run → 3. delete the reject block with a one-line D6-R comment ("read-only, creator-scoped; the DECISION stays durable-gated in decideClaimRequest") → 4. GREEN run.
5. Commit: `feat(groups): anon creator can list claim requests (D6-R)`

**Guard:** `decideClaimRequest.ts:167` and `requestClaimShadow.ts:53` are NOT touched. Their existing anon-reject tests must stay green — they pin the new boundary.

### Task 3: Client — ungate create-screen chips (+ retire #840 CTA)

**Files:**
- Modify: `lib/features/groups/screens/create_group_screen.dart:364-395`
- Test: `test/features/groups/create_group_shadow_members_test.dart:169` (flip)

**Step 1 (RED):** rewrite the `:169` test (`'shadowAddRequiresLink hint, NOT the offline hint'`) to assert: with an ANON user (override `isDurableUserProvider`/auth as the file already does) and online, the chips field is **enabled**, no `shadowAddRequiresLink` text, and no `GroupKeys.createLinkAccountCta`. Grep the file for other assertions on the CTA/hint and flip them in the same pass.

**Step 2:** run `flutter test test/features/groups/create_group_shadow_members_test.dart` → FAIL.

**Step 3 (GREEN):** in `create_group_screen.dart`:
- `ShadowMemberChipsField.enabled`: `ref.watch(connectivityProvider) == ConnectivityStatus.online` only (drop `&& ref.watch(isDurableUserProvider)`).
- `disabledHint`: `null` (connectivity messaging is handled inside the field — see `shadow_member_chips_field.dart:35-47` doc).
- Delete the `if (!ref.watch(isDurableUserProvider))` link-account `TextButton` block (#840) entirely.
- Gate R1: also retire the now-dead `GroupKeys.createLinkAccountCta` constant (`group_keys.dart:49`) + any test references (analyze won't catch a dead const).

**Step 4:** re-run file → PASS. **Step 5:** commit `feat(groups): create-screen add-by-name available to anonymous creators (D6-R)`.

### Task 4: Client — ungate group-settings members section

**Files:**
- Modify: `lib/features/groups/widgets/group_members_section.dart:42-46,76-86`
- Test: `test/features/groups/group_members_section_shadow_test.dart` (flip anon leg)

**Steps:** RED: flip the anon-creator expectation (affordance PRESENT, no `shadowAddRequiresLink` footer; non-creator still sees `groupMembersCreatorOnlyNote`). GREEN: `canAddByName = isCurrentUserCreator;` (drop the `isDurableUserProvider` watch + stale #818 comment), footer text becomes unconditional `groupMembersCreatorOnlyNote` under `if (!canAddByName)`. Run file → PASS. Commit `feat(groups): members-section add-by-name ungated for anon creators (D6-R)`.

### Task 5: Client — ungate group-detail "add person" action

**Files:**
- Modify: `lib/features/groups/screens/group_detail_screen.dart:159,258-277`
- Test: grep `groupDetailAddPersonAction` under `test/` — flip any anon-gated assertion; if none exists, add one leg to the existing group-detail widget test: anon creator sees the action.

**Steps:** RED→GREEN: flip the existing `group_detail_screen_test.dart` ~`:1315` leg ("#818: anonymous creator gets no People add-person action") to assert the action IS present; delete `isDurableUser` from both ternaries (`:265,:272`) and the now-unused local at `:159`; rewrite the stale `#818` rationale comment at `:253-258` (Gate R1 — it would contradict the new behavior). Run the group-detail test file(s) → PASS. Commit `feat(groups): group-detail add-person ungated for anon creators (D6-R)`.

### Task 6: Client — claim decisions pre-gated by the durable sheet

**Files:**
- Modify: `lib/features/groups/widgets/claim_requests_section.dart` (`_decide`, before `setState`)
- Test: `test/features/groups/claim_requests_section_test.dart` (or the existing file covering this widget — locate by `grep -rln ClaimRequestsSection test/`)

**Step 1 (RED):** new widget test: override `isDurableUserProvider` → false, pump the section with one fake pending request, tap Approve. Assert: `decideClaimRequest` on the mocked `firebaseFunctionsServiceProvider` was **never called**, and the durable-credential sheet is shown (`find.byType(DurableCredentialSheet)` — import from `durable_credential_sheet.dart`; if the type is private, key the sheet or assert on its Google CTA text). Existing durable-path tests stay untouched (they pin that a durable creator's tap calls the service).

**Step 2:** run → FAIL (service called, no sheet).

**Step 3 (GREEN):** in `_decide` — placement pinned by Gate R1 (adversary): AFTER the `if (_busy) return;` guard and the `setState(_busy = true)` (so a double-tap can't open two sheets), with an explicit `_busy` reset on the cancel path (so "Not now" doesn't leave the button spinning forever — the `finally` that normally resets `_busy` lives inside the later try block and is skipped by an early return):

```dart
if (!ref.read(isDurableUserProvider)) {
  final linked = await showDurableCredentialSheet(context);
  if (!linked || !mounted) {
    if (mounted) setState(() => _busy = false);
    return;
  }
}
```

(`showDurableCredentialSheet` returns `Future<bool>` and force-refreshes the ID token on success — `durable_credential_sheet.dart:30,69` — so the follow-through callable sees the non-anon provider. In the widget test, assert the sheet via `Key('durableGate.continue')` / the `durableGateTitle` string — the sheet's widget type is private. New imports: `auth_provider.dart`, `durable_credential_sheet.dart`.)

**Step 4:** run file → PASS. **Step 5:** commit `feat(groups): claim decisions prompt account link for anon creators (D6-R)`.

### Task 7: l10n — retire `shadowAddRequiresLink`

**Files:**
- Modify: `lib/l10n/app_en.arb:2556-2559`, `lib/l10n/app_ar.arb` (matching key), regenerate `lib/l10n/generated/*`
- Test: `test/unit/generated_l10n_surface_test.dart` (memory: it enumerates keys — update its expectation for the removed key)

**Steps:** delete the key+meta from both arbs → `flutter gen-l10n` → fix `generated_l10n_surface_test` → `flutter analyze` (catches any missed `.shadowAddRequiresLink` reader — Tasks 3/4 removed both) → run the l10n test → commit `chore(l10n): drop shadowAddRequiresLink (D6-R retired the gate)`.

### Task 8: Docs + full verification

**Files:**
- Modify: `CLAUDE.md` (Key Invariants → "Name-based members" bullet: creator add-by-name no longer durable-gated; claim DECISIONS are the durable boundary; joins anon-legal per #648, unchanged)
- This plan doc: already the D6-R record.

**Steps:**
1. `flutter analyze` clean.
2. `flutter test test/features/groups/ test/unit/` green; `cd functions && bash ../tool/run_firebase_emulator_tests.sh` full suite green.
3. `bash tool/check_theme_purity.sh` (widget files touched).
4. Commit docs: `docs(claude): record D6-R — durable boundary moved to claim decisions`.

### Task 9: PR + deploy ceremony

- One PR, body `Spec: docs/plans/2026-07-06-anon-shadow-sandbox.md`, RED evidence pasted from Tasks 1/3/6. No `Closes #N` (no issue; reference this plan).
- `/automerge <N>` — this is GATE-category (functions/**), so the diff review + refuter run at merge time.
- After merge: `tool/pending_deploy.sh` → deploy ceremony for `addShadowMember` + `listGroupClaimRequests` (no rules change; "no real users yet → server changes deploy freely").
