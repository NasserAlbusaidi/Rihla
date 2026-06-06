# Spec: server-authoritative group self-leave (#290)

**Status:** spec — pre-implementation. Gate-category (money + `firestore.rules` + Cloud Functions). Must pass a fresh-context Opus Gate review before code.

## 1. The bug (verified against code 2026-06-06)

Leaving a group while offline orphans debt. Verified callsites:

- `group_danger_section.dart:198-254` `_executeLeave`: the settle-before-leave guard is **only** inside `if (balances != null && uid != null)` (line 205). When `groupBalancesProvider.valueOrNull` is **null** (offline / slow load / provider error) it falls straight through to `leaveGroup()` with no balance check.
- `group_provider.dart:304-325` `leaveGroup()`: a direct Firestore `batch` — `memberIds: arrayRemove([uid])` on the group doc + `delete` of the member doc (found by `where('userId','==',uid)`). Doc comment even says "gate is UI-side."
- `security/firestore.rules:309-313` `validSelfLeave()`: only asserts exactly one member (self) was removed (`removesExactlyOneExistingMember()` + `!(uid in memberIds-after)`). **No `balance==0`** — unlike `deleteGroup`, which is server-gated.

Result: a passenger on a flaky connection taps **Leave**, the guard no-ops on null balances, they're removed **while still owing** → the ledger nets non-zero with a departed party that can't be collected from.

`deleteGroup` is the correct mirror (already shipped, #190): server-authoritative callable recomputes net, refuses on non-zero, direct path locked at rules (`allow delete: if false`). Client balance check there is **UX-only short-circuit** (`_executeDelete`, lines 256-302, comment: "let the SERVER decide — it is the sole authority").

## 2. Fix shape (three layers, mirror deleteGroup)

### 2.1 New callable `functions/src/callables/leaveGroup.ts`

Signature: `leaveGroup({ groupId }) -> { groupId, mode: 'left', alreadyLeft: boolean }`. Config `{ enforceAppCheck: true }` (match deleteGroup; App Check is the real per-actor control per CLAUDE.md — **no** dedicated per-IP/throttle, #197).

**No lock, no rate-limit — intentional (Gate R1 [P2-3]).** Unlike `deleteGroup` (which acquires a `deletingInProgress` lock + a `deleteGroupAttempts` 5/hr throttle because it runs a multi-flush cascade), leave is a single small atomic batch touching only the leaver's own membership — no group-wide lock is needed (concurrent leaves each remove a different uid; idempotent re-runs are safe per step 4). Leave-spam is already bounded upstream: re-entry requires the rate-limited `joinGroupByInviteCode` (5/hr/UID), so a churn loop can't exceed join's throttle. `enforceAppCheck` is the per-actor control.

Flow:
1. `if (!request.auth) throw unauthenticated`.
2. Validate `groupId` is a non-empty string with no `/` (mirror deleteGroup:704).
3. `uid = request.auth.uid`. Read `groups/{groupId}`. If not exists → `not-found`.
4. **Membership / idempotency:** query `members where userId == uid` (returns ALL matches — the creator doc is uuid-keyed with a `userId` field, #294). `isMember = uid in group.memberIds`. Short-circuit `{ groupId, mode:'left', alreadyLeft:true }` ONLY when the leaver is fully absent (`!isMember && memberDocs.empty`). If EITHER `isMember` OR any member doc exists, **proceed** with gate + removal — this self-heals a partially-completed prior leave (uid still in `memberIds` but doc gone, or doc present but uid already removed) by re-asserting both writes idempotently (arrayRemove of an absent uid is a no-op; delete of an absent doc is skipped) (Gate R1 [P2-2]).
5. **Balance gate (the fix):** `const { net } = await recomputeNet(db, groupRef)`. `const leaverNet = net.get(uid) ?? new Money(0)`. If `!leaverNet.isZero()` → `throw failed-precondition('You have an unsettled balance and cannot leave the group.')`.
6. **Removal (atomic batch):** `arrayRemove([uid])` from `memberIds` + `updatedAt: serverTimestamp` on the group doc; `delete` **every** member doc matching `userId == uid` (robustness: creator doc is uuid-keyed with `userId` field, plus a stale rejoin dup — see CLAUDE.md member-doc keying note / #294); write a `member_left` activity doc (see 2.4). One `WriteBatch`, one commit.
7. Return `{ groupId, mode:'left', alreadyLeft:false }`.

**Gate semantics — why leaver-net, not whole-group:** leave removes ONE member; others keep their balances. Correct gate = the *leaver* is square. Worked: A owes B 10, C square. C leaves → `net[C]==0` → allowed, no orphan (A still owes B). A leaves → `net[A]==−10` → blocked. B (creditor) leaves → `net[B]==+10` → blocked (else A owes a ghost). Both debtor and creditor are correctly blocked; a square non-party leaves freely. `net.get(uid)` absent ⇒ never participated ⇒ owes nothing ⇒ allowed. `isZero()` is exact because the allocators close residuals (incl. #223 in-tolerance close-out) — same exactness `deleteGroup`'s per-actor gate relies on.

**Removal = hard-delete (preserve current behavior), NOT a tombstone — and why that is conservation-safe.** The leaver's member doc is hard-deleted (mirror today's client `group_provider.dart:323` `batch.delete`), NOT tombstoned. Conservation proof (Gate R1 challenge on the orthogonal split-recipient / #249 axis):
- **`leaveGroup` never touches event `participantIds`** — it writes only `groups/{id}.memberIds` + the member doc. So for any event where the leaver is a participant (the filed bug's whole scenario — a passenger on a flaky connection), the per-event universe is `Set(participantIds)` ∪ … and is **byte-identical pre/post leave**. Every *other* member's paid/owed/settlement fold is therefore unchanged ⇒ their balances are unchanged ⇒ the group sum is preserved. Hard-delete strands nothing for a normal participant.
- **The gate is self-consistent with conservation.** `recomputeNet` is the same oracle the client ledger uses (`expense_provider.dart:121-123` `allMemberIds`/`liveMemberIds` mirror `deleteGroup.ts:519-527`). A leaver passes ONLY if `net[leaver]==0` under those exact drop semantics. The only universe-shift caused by removing the leaver's member doc is to the **leaver's own** fold status in events where they are a NON-participant payer/settler/split-recipient — and in that exotic case the same drop makes `net[leaver]` non-zero (e.g. an unoffset group-scope settlement vs a dropped non-participant owed) ⇒ the gate **blocks** the leave. So a leaver can only pass when their removal is balance-neutral.
- **Why NOT tombstone (rejecting Gate R1 [P1-1]):** (a) "mirror `deleteAccount`" over-simplifies — `deleteAccount.ts:212-380,575-598` performs a full uid→tombstoneId **identity scrub** across `memberIds` + every expense/settlement/activity reference (privacy erasure for account *deletion*); leave is *migrate-not-scrub* (the leaver is a real participant whose name must stay in the ledger). (b) A minimal `isTombstone:true` instead would **change** balance semantics on the #249 edge — it would start folding a non-participant split-recipient's owed that is intentionally dropped while they are live (`deleteGroup.ts:599-601` gate `allMemberIds && !live`), i.e. tombstone ≠ behavior-preserving. (c) `watchMembers` (`group_provider.dart:385-396`) does NOT filter `isTombstone`, so a tombstoned leaver could surface in the roster — a UX regression that belongs to the unbuilt tombstone/shadow membership model (#278), not a money-gate PR. The #249 non-participant-split-recipient conservation gap is **pre-existing** (exists while the member is live, on `main`'s client hard-delete today), CLAUDE.md-tracked ("fix at the caller's universe construction on BOTH client and server"), and explicitly out of scope here — see §3.

### 2.2 Shared balance oracle (extraction)

`recomputeNet` + its full dependency set (the `Money` Decimal clone, MoneySerializer port, split decode, allocators, `isLiveDoc`/`stringArray`/`timestampMillis`/`isEventInDeleteBalanceScope`, `RecomputeResult`) currently live in `deleteGroup.ts:29-690`. **Extract verbatim** to a new shared module `functions/src/callables/groupNetBalance.ts`; `deleteGroup.ts` and `leaveGroup.ts` both import it.

Rationale: CLAUDE.md makes the single-balance-oracle / byte-for-byte parity load-bearing. A second hand-rolled copy in `leaveGroup.ts` is guaranteed drift; making the oracle a shared module makes "one oracle" **structural**, not implicit. The move is mechanical (no logic change) and proven green by the existing `deleteGroup.test.ts` + `delete_group_balance_parity_test.dart` (behavior unchanged ⇒ tests stay green = the proof). `recomputeNet` already works unmodified for leave: with no delete lock, `deletingInProgress` is false ⇒ `includeSoftDeletedSinceMs = null` ⇒ only live events count — exactly leave's requirement.

**Fallback if Gate rejects extraction as scope creep:** `export { recomputeNet, Money, RecomputeResult }` from `deleteGroup.ts` and import into `leaveGroup.ts` (no code moves). Less clean (callable importing a sibling callable's internals) but smaller diff. Default = extraction.

### 2.3 Rules change (`firestore.rules`)

Remove `validSelfLeave()` from the group `allow update` (line 331-335) → `allow update: if groupAllowsClientWrites(groupId) && (validCreatorMetadataUpdate() || validMemberIdsRefresh() || validCreatorRemoveMember());`. Keep the `validSelfLeave` **function** defined or delete it (no other caller — grep-verified); deleting it is cleaner.

**Sufficiency proof (the direct path is fully closed by this one removal):** self-leave needs BOTH the group-doc `arrayRemove` AND the member-doc delete, in one atomic batch. After removing `validSelfLeave`:
- Full batch (group update + member delete): group update matches no branch → **denied** → atomic batch fails.
- Member-doc delete alone: `validMemberDelete` self-branch (rules:795-798) requires `!(uid in groupAfterMemberIds())`; with memberIds unchanged the uid is still present → **denied**.
So no client path can self-remove. `validMemberDelete`'s self-branch becomes unreachable for the direct path but is harmless to leave in place; **do NOT remove `validMemberDelete`** — its creator-branch still backs creator-remove. The callable uses Admin SDK (rules-bypassing) so the removal still works.

### 2.4 Activity logging moves server-side

Today `_executeLeave` fire-and-forget logs `member_left` to `groups/{id}/activity` **before** leaving (group_danger_section.dart:231-239). With a callable this can't stay client-side: logging before the call risks a phantom "left" if the gate refuses; logging after the call is **denied** (rules `validGroupActivityCreate` requires `isGroupMember`, and they're no longer a member). So the **callable** writes it (Admin SDK, atomic with removal). Doc shape must match `group_activity_service.dart:124-133` exactly: keys `{id (uuid), type:'member_left', actorId:uid, actorName, description:'left the group', metadata:{}, timestamp: new Date().toISOString()}`. `actorName` = the leaver's **raw member-doc `displayName` field** read before delete (NOT a disambiguated/`(former member)`-suffixed render — the server can't read the client's `settingsProvider.deviceName`, and the member-doc field is the canonical server-side source; Gate R1 [P2-1]); fallback `'Someone'` only if the doc/field is absent. The reader `GroupActivityLog.fromFirestore` consumes `timestamp` as an ISO string — matched. Remove the client-side activity log from `_executeLeave`.

### 2.5 Client changes

- `firebase_functions_service.dart`: add `leaveGroup({required String groupId})` mirroring `deleteGroup` (lines 32-39).
- `group_provider.dart` `leaveGroup()` (304-325): replace the direct batch with `_ref.read(firebaseFunctionsServiceProvider).leaveGroup(groupId: groupId)`; update the doc comment (drop "gate is UI-side"); remove now-unused Firestore-batch imports if any become dead.
- `group_danger_section.dart` `_executeLeave` (198-254): invert the null path to mirror `_executeDelete` — balance check becomes **UX-only short-circuit** (loaded + leaver non-zero → settle hint, no round trip); on null/loading **fall through to the callable** (server is authority). Map `FirebaseFunctionsException`: `failed-precondition` → `groupSettleBeforeLeaving` snackbar (with Settle-up action); `not-found` → treat as already-left, nav `/home`; else `groupFailedLeave`. Drop the client activity log (now server-side).

### 2.6 Deploy plumbing

- `functions/src/index.ts`: add `export { leaveGroup } from './callables/leaveGroup';` (as an `export {…} from` re-export so the `list_expected_functions.sh` awk extractor sees it — CLAUDE.md deploy-drift note). **No test edit needed:** `release_workflow_gate_test.dart` (`:588-623`) does NOT hardcode an expected-function set — it runs the awk extractor and independently re-extracts from `index.ts` with a Dart regex, then asserts the two agree. The re-export makes both extractors pick up `leaveGroup` automatically; the test stays green with zero edits (Gate R1 [P1-2], verified against `:611-622`). Re-exporting is still mandatory or the deploy-drift check would flag a missing/extra function.
- **Deploy-ordering hazard (accepted, same precedent as deleteGroup #190):** deploying the rules that drop `validSelfLeave` breaks leave for already-installed clients (they do a direct batch) until they update. Installed base is the tiny closed-test "first" track. Sequencing: deploy callable + rules to prod (deploy ceremony) **before** shipping the client. The new client must ship close behind. This PR is code-only; the prod deploy + release tag are the existing ceremony (PRODUCTION-READINESS gate, not flipped here).

## 3. Out of scope (file as follow-ups — avoid the half-done scar)

- **Creator-remove has the identical bug.** `removeMember` (group_provider.dart:332-346, creator removes another member) is also a direct batch; its client balance gate (members section) is also skipped when balances null. Same fix shape (server gate). **Not** #290 (self-leave). → new issue.
- **Creator self-leave dangles `createdBy`.** Current rules already let the creator self-leave (`isMember()`); after they leave, `deleteGroup`'s `createdBy === uid` check can never pass. Pre-existing; this spec preserves current behavior (creator may leave if square). → note on #245/#278 cluster, not fixed here.
- **Leave ∩ #249 conservation (the Gate R1 [P1-1] edge).** A leaver who is a NON-participant split-recipient (removed from an event's `participantIds` but still referenced in old `splitDistribution`/`customSplitParticipants`) is dropped from the universe by hard-delete — same as while they were live, and the gate blocks the leave if that drop unbalances them. The general fix (preserve departed split-recipients via tombstone-aware universe construction on both client + server) is the #249 cluster's job, not #290's. → fold into #249, not bundled here.

## 4. Tests (failing-first)

1. **Jest emulator `functions/test/callables/leaveGroup.test.ts`** (mirror deleteGroup.test.ts harness): (a) leaver with non-zero net → rejects `failed-precondition`, member doc + memberIds untouched; (b) square leaver → memberIds loses uid, member doc(s) deleted, `member_left` activity doc written; (c) not-a-member → `alreadyLeft:true`, no writes; (d) unauth → `unauthenticated`; (e) creator-uuid-keyed member doc (userId field ≠ doc id) is found & deleted (the #294 lookup); (f) creditor (net > 0) → blocked too.
2. **Rules test** (`firestore-rules-publish-readiness.test.ts`): a member's direct `arrayRemove`-self batch (and lone member-doc self-delete) now **assertFails**. Creator-remove still **assertSucceeds**.
3. **Parity stays green:** `deleteGroup.test.ts` + `delete_group_balance_parity_test.dart` unchanged-and-passing = proof the extraction is behavior-preserving.
4. **Dart widget `group_settings_screen_test.dart`:** leave with `balances == null` now routes through the (faked) `firebaseFunctionsServiceProvider.leaveGroup` instead of falling through to a direct leave; faked `failed-precondition` → settle-before-leaving snackbar; success → nav home. Reuse the existing fake-functions-service override pattern from the delete tests.

## 5. Files touched

- NEW `functions/src/callables/leaveGroup.ts`
- NEW `functions/src/callables/groupNetBalance.ts` (extracted oracle)
- `functions/src/callables/deleteGroup.ts` (import oracle; delete the moved code)
- `functions/src/index.ts` (+export)
- `security/firestore.rules` (drop `validSelfLeave` from allow-update)
- `lib/core/services/firebase_functions_service.dart` (+leaveGroup)
- `lib/features/groups/providers/group_provider.dart` (`leaveGroup` → callable)
- `lib/features/groups/widgets/group_danger_section.dart` (`_executeLeave` UX-only gate)
- NEW `functions/test/callables/leaveGroup.test.ts`
- `functions/test/firestore-rules-publish-readiness.test.ts` (blocked-direct-leave assertions)
- `test/features/groups/group_settings_screen_test.dart` (null-balance routes to callable)
- (NOT `test/unit/release_workflow_gate_test.dart` — extracts dynamically, no edit; see §2.6)

## 6. Done = green

`flutter analyze` clean; `flutter test` (group settings + release gate) green; `cd functions && npm run build && npm run test:emulator -- leaveGroup.test.ts deleteGroup.test.ts firestore-rules-publish-readiness.test.ts` green; spec re-checked against code; PR carries `Closes #290`; follow-up issues filed for §3.
