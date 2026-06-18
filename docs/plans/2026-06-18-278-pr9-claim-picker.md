# PR9 — Claim picker on join: the last #278 slice (CLOSES #278)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> Design source = `docs/plans/2026-06-17-278-claim-merge.md` §PR9 (epic Gate-converged, D1–D9 locked). This doc re-grounds that design against the CURRENT code (all anchors re-verified 2026-06-18, post-PR8-merge `ab323191`) and is the concrete target for `/run-the-gate` BEFORE any PR9 code.
>
> **Gate-CATEGORY** — one new Cloud Function (`listUnclaimedShadows`, an auth surface) + the client orchestrates two money-inheriting flows (`requestClaimShadow` discovery, `decideClaimRequest` approval invokes the PR7 re-key). MUST clear a fresh-context Opus Gate before code; re-Gate the diff at merge via `/automerge`.

## Goal

Surface claimable placeholder ("shadow") members to a real joiner with an "is this you? claim / I'm new" choice and a **hard, irreversible-by-design confirmation** (D3); give the **creator** an approve/decline surface for pending claim requests. This is what makes the add-by-name limitation disappear: a name collision on join becomes a *claim offer* instead of a dead-end. **#278 CLOSES when this ships.**

## Architecture

Backend is already done (PR1–PR8, merged): `addShadowMember`, the `claimShadowEngine`, and the 4 PR8 callables (`requestClaimShadow`, `decideClaimRequest`, `listMyClaimRequests`, `listGroupClaimRequests`). PR9 adds **one** read-only discovery callable (`listUnclaimedShadows`) + the **entire client surface**: 5 typed callable wrappers in `GroupService`, the join-screen picker/permanent-confirm/waiting flow, the creator approve-UI, l10n EN+AR, and widget tests. Per **D8 (locked)** the requester does NOT call `joinGroupByInviteCode` on the claim path — `decideClaimRequest(approve:true)` performs the re-key that makes them a member, so the requester's client *requests* then *polls* `listMyClaimRequests` until `status:'claimed'`, then enters the group.

## Tech Stack

Cloud Functions (Node 22 / TypeScript, `firebase-functions/v2`, Admin SDK), Jest + Firestore emulator (Java 21). Flutter / Riverpod / Dart client; `flutter_gen-l10n` for ARB; `mocktail` + `FakeFirebaseFirestore` widget tests.

---

## OWNER DECISIONS already locked upstream (do NOT re-litigate)

| # | Decision | PR9 consequence |
|---|---|---|
| **D1** | Creator-approval. | The creator approves via `decideClaimRequest`; PR9 builds the creator's approve/decline UI. |
| **D3** | Claims are FINAL — no un-claim. | The claim-confirmation sheet is a HARD permanent warning requiring an affirmative tap (not a default-OK). |
| **D6** | Durable (non-anon) account to claim. | `listUnclaimedShadows` rejects anon (mirrors the 4 PR8 callables). The join screen's existing durable-credential gate (`join_group_screen.dart:111-119`, #441) already forces a link before any claim too. |
| **D7** | The claimed member doc KEEPS the shadow's name. | The requester's typed name on the join screen feeds `requestClaimShadow`'s `displayName` only as the creator-facing "who is asking" label — it is NOT the adopted name. The picker shows the **shadow's** name as the spot being claimed. |
| **D8** | Request BEFORE join; approval re-keys. | The claim path does NOT call `joinGroupByInviteCode`. Post-approval the requester is already a member (engine `arrayUnion`), so the waiting screen navigates straight into the group on `status:'claimed'`. |

---

## PR9 owner decisions (NEW — locked for this slice; flagged to the Gate)

| # | Decision | Rationale |
|---|---|---|
| **P9-1** | **Creator learns of requests by poll-on-open, NOT push.** The creator sees pending requests when they open Group Settings (a callable fetch). No FCM trigger on `claimRequests` create in PR9. | Keeps PR9 client-only + one read callable; a `claimRequests`-create notifier is backend-trigger + deploy surface = scope creep. **File a follow-up issue** for a creator push notification. The requester is told "waiting for the creator to approve" and nudges out-of-band. |
| **P9-2** | **Waiting screen uses manual "Check again" + check-on-mount, NOT an auto-poll timer.** | A `Timer.periodic` poll widget would trip the project's never-settling-timer widget-test traps (ConnectivityNotifier / EmptyStateView). One fetch on mount + a manual refresh is fully testable. Auto-poll-on-resume is a noted enhancement. |
| **P9-3** | **Re-entry is handled by `requestClaimShadow` idempotency, NOT a persisted resume.** If the requester re-enters the code and re-claims the same shadow, the callable re-writes the same pending doc (no duplicate) and lands them back on the waiting screen. | No client persistence of "I have a pending request" needed for v1. |
| **P9-4** | **`listUnclaimedShadows` has NO membership gate** (pure pre-join discovery), and exposing shadow display names to a valid-invite-code holder is an ACCEPTED, invite-code-gated disclosure. | A code-holder can join and see all member names anyway; `requestClaimShadow` already reveals shadow existence to code-holders. Same trust boundary. The callable returns ONLY `{shadowMemberId, displayName}` — no balances, no uids of real members. |
| **P9-5** | **The #279 join collision guard stays UNCHANGED.** "No, I'm new" routes to the normal `joinGroupByInviteCode`; a colliding name still throws `already-exists` → the join screen surfaces an actionable "claim it above or pick another." | The collision IS the claim trigger; weakening the guard would let a stranger silently take a name. The UI routes around it; the rule does not move. |

---

## Scope guard

- **IN:** `listUnclaimedShadows` callable + test + re-export; 5 typed client wrappers (`listUnclaimedShadows`, `requestClaimShadow`, `decideClaimRequest`, `listMyClaimRequests`, `listGroupClaimRequests`) + result models + override seams; the join-screen discovery → picker → permanent-confirm → waiting flow + "I'm new" fallback; the creator approve/decline UI in Group Settings; l10n EN+AR; widget tests; the CLAUDE.md "Name-based members" invariant flip; `Closes #278`.
- **OUT (do NOT build):** un-claim/reversal (D3); a creator push notification (P9-1 → follow-up issue); auto-poll-on-resume of the waiting screen (P9-2 enhancement); any change to `firestore.rules` (no rules surface in PR9 — `claimRequests` shipped its block in PR8); any change to the `claimShadowEngine` or the 4 PR8 callables (frozen); any change to the #279 join guard (P9-5).
- The backend re-key correctness (PR7) and authz (PR8) are DONE and frozen — PR9 only consumes them.

---

## Verified current-code anchors (re-grepped 2026-06-18, post-`ab323191`)

**Backend (the sibling to mirror + the predicate to match):**
- **`listMyClaimRequests.ts` (FULL) is the template for `listUnclaimedShadows`** — `onCall({enforceAppCheck:true})`, `unauthenticated` guard, anon→`permission-denied` (D6), `normalizeInviteCode(request.data?.inviteCode)`, `resolveGroupIdByInviteCode(db, code)` (`not-found` on a bad code), NO membership gate, a `.collection(...).where(...).get()`, a `.map()` to a typed output, `Timestamp.toMillis()` for dates. Copy this shape verbatim.
- **The "claimable shadow" predicate to MATCH** (`requestClaimShadow.ts:97-101`):
  ```ts
  shadow.isShadow === true && shadow.isTombstone !== true && memberIds.includes(shadow.userId)
  ```
  `listUnclaimedShadows` applies the SAME predicate to EVERY member doc (not a single `.where('userId','==',x)` lookup). A member whose `userId ∉ memberIds` (a half-deleted relic) is NOT listed. A `claimed`-but-not-yet-removed relic can't exist (the engine deletes the shadow doc atomically with `memberIds` removal), but the `isTombstone !== true` + `memberIds.includes` guards make the list self-correcting regardless.
- **Helpers (already extracted, import-ready):** `normalizeInviteCode`, `resolveGroupIdByInviteCode` (`functions/src/callables/shared/inviteCode.ts`); `validId` (`functions/src/callables/shared/ids.ts`).
- **`index.ts` re-exports (`:6-15`):** add a single-line `export { listUnclaimedShadows } from './callables/listUnclaimedShadows';` re-export **anywhere in the export block — ordering is cosmetic** (Gate R1 P3: the block is feature-grouped, NOT alphabetical; `tool/list_expected_functions.sh` ends in `sort -u` and `release_workflow_gate_test.dart:622` compares `.toSet()`, so order is functionally irrelevant). What DOES matter: it must be the `export { … } from` form — a bare `export const` escapes the awk extractor (CLAUDE.md). After: `bash tool/list_expected_functions.sh` shows `listUnclaimedShadows`; `flutter test test/unit/release_workflow_gate_test.dart` green.
- **The 4 PR8 callable shapes (for the wrappers):**
  | callable | input | output |
  |---|---|---|
  | `requestClaimShadow` | `{inviteCode, shadowMemberId, displayName?}` | `{requestId, status, groupId}` |
  | `decideClaimRequest` | `{groupId, requestId, approve:boolean}` | `{requestId, status, alreadyClaimed:boolean}` |
  | `listMyClaimRequests` | `{inviteCode}` | `{requests:[{requestId, shadowMemberId, shadowDisplayName, status, createdAtMillis}]}` |
  | `listGroupClaimRequests` | `{groupId}` | `{requests:[{requestId, requesterUid, requesterDisplayName, shadowMemberId, shadowDisplayName, status, createdAtMillis}]}` |
  | **`listUnclaimedShadows`** (NEW) | `{inviteCode}` | `{shadows:[{shadowMemberId, displayName}]}` |
  - **Engine error codes surfaced through `decideClaimRequest` (drive the creator-UI copy):** `permission-denied` (non-creator/anon), `not-found` (group/request gone), `failed-precondition` (already-decided, OR engine "claimer already present", OR "already claimed"), `internal` ("Claim produced an inconsistent balance…" — **RETRYABLE**, surface "try again", NEVER terminal-success). Full table: `2026-06-17-278-pr8-claim-authz.md` §"Engine error codes".
- **Test harness:** `functions/test/callables/claimRequest.test.ts` (the PR8 suite — local `seedGroup`/`seedMember`/`seedShadow` helpers + `clearFirestore` from `../fixtures`). Scoped emulator run:
  ```bash
  cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/listUnclaimedShadows.test.ts" npm run test:emulator
  ```

**Client:**
- **Wrappers home:** `GroupService` in `lib/features/groups/providers/group_provider.dart`. Override seams live on `GroupService.withFirestore(...)` (`:74-103`); the existing wrapper idiom is `_addShadowMemberCallableOverride` / `addShadowMember()` (`:378-398`) — `override ?? FirebaseFunctions.instance.httpsCallable('name').call({...})`, `on FirebaseFunctionsException` → mapped Exception. Mirror exactly.
- **Wrapper test pattern:** `test/features/groups/group_members_section_shadow_test.dart` — `class _MockGroupService extends GroupService` (`super.withFirestore(ref, FakeFirebaseFirestore())`) overriding the wrapper methods + `groupServiceProvider.overrideWith((ref) => _MockGroupService(...))`. Mirror for the new wrappers.
- **Join screen:** `lib/features/groups/screens/join_group_screen.dart` — `JoinGroupScreen` (`:34`). Code field auto-submits at 6 chars (`:281` `if (value.length == 6) _joinGroup();`); `_joinGroup()` (`:91-190`) routes through `durableCredentialGateProvider.ensure(...)` (`:111-119`) THEN `ref.read(groupServiceProvider).joinGroup(inviteCode)` (`:142`) THEN `context.pushReplacement('/group/${group.id}')` (`:175`). Error mapping `_errorMessage()` (`:192-214`) already maps "already taken in this group" → `groupJoinNameTaken`. Keys: `GroupKeys.joinGroupButton` (`:288`).
- **Creator surface:** `lib/features/groups/screens/group_settings_screen.dart` (`:24-107`, `isCreator = currentUserId == group.createdBy` `:44`) → `GroupMembersSection` (`lib/features/groups/widgets/group_members_section.dart:26-276`, takes `isCurrentUserCreator`). Member rows `:83-136`; the creator-only "Manage" affordance `:49-53`. The pending-requests subsection mounts here, creator-gated.
- **l10n:** `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb`; `l10n.yaml`; codegen `flutter gen-l10n` → `lib/l10n/generated/app_localizations.dart` (DO NOT hand-edit the generated file). Access `context.l10n.key` (`lib/core/extensions/build_context_l10n.dart`). Key style: `groupXxx` camelCase + `@key` description; placeholders `{name}` are `{}` objects in EN, value-only in AR. Existing siblings to match: `groupShadowNotJoinedBadge`, `groupAddPersonTitle`, `groupJoinNameTaken`.
- **Existing shadow UI to reuse, not duplicate:** `_buildShadowBadge` (`group_members_section.dart:155-173`, "Not joined yet" pill); `RAvatar(size:..., name: displayName)` for people; `GroupKeys.shadowBadge(id)`.

---

## The new callable — `listUnclaimedShadows(inviteCode)` → `{shadows:[{shadowMemberId, displayName}]}`

Mirror `listMyClaimRequests.ts` exactly. `enforceAppCheck:true`.
1. `request.auth` else `unauthenticated`.
2. anon → `permission-denied` (D6), BEFORE any read.
3. `code = normalizeInviteCode(request.data?.inviteCode)` (invalid → `invalid-argument`).
4. `groupId = resolveGroupIdByInviteCode(db, code)` (bad/unknown code → `not-found`).
5. Load group; `isDeleted`/`deletingInProgress`/missing → `not-found` (mirror `requestClaimShadow:69-77`). **(P9-4: no membership gate.)**
6. `memberIds = group.memberIds` (string-filtered). Query `groups/{gid}/members` and keep docs where `isShadow === true && isTombstone !== true && memberIds.includes(userId)`. (Use a `.where('isShadow','==',true).get()` then filter `isTombstone`/`memberIds` in code — the same shape as `requestClaimShadow`'s validation, applied across all shadow docs.)
7. Return `{ shadows: docs.map(d => ({ shadowMemberId: d.userId, displayName: d.displayName ?? 'Member' })) }`. Never include real members, balances, or uids.

> **Info-disclosure note (P9-4, for the Gate):** the only data crossing the boundary is shadow placeholder *names* + their opaque uuids, to a caller proving knowledge of a valid invite code. This is strictly less than what joining reveals. No real-member identity leaks (shadows only). Accepted.

---

## Client wrappers + result models (`GroupService`)

Add to `group_provider.dart`. Each wrapper: try override seam → else `FirebaseFunctions.instance.httpsCallable('<name>').call({...})` → map result → `on FirebaseFunctionsException` rethrow a mapped `Exception`. Add the override fields to `GroupService.withFirestore(...)` (5 new optional `…Override` params, mirroring `_addShadowMemberCallableOverride`).

**Result models** (small immutable value classes — put in `lib/features/groups/models/claim_models.dart`):
```dart
class UnclaimedShadow {
  const UnclaimedShadow({required this.shadowMemberId, required this.displayName});
  final String shadowMemberId;
  final String displayName;
}
class ClaimRequestResult { // requestClaimShadow
  const ClaimRequestResult({required this.requestId, required this.status, required this.groupId});
  final String requestId; final String status; final String groupId;
}
class ClaimDecisionResult { // decideClaimRequest
  const ClaimDecisionResult({required this.requestId, required this.status, required this.alreadyClaimed});
  final String requestId; final String status; final bool alreadyClaimed;
}
class MyClaimRequest {
  const MyClaimRequest({required this.requestId, required this.shadowMemberId, required this.shadowDisplayName, required this.status, this.createdAtMillis});
  final String requestId, shadowMemberId, shadowDisplayName, status; final int? createdAtMillis;
}
class GroupClaimRequest {
  const GroupClaimRequest({required this.requestId, required this.requesterUid, required this.requesterDisplayName, required this.shadowMemberId, required this.shadowDisplayName, required this.status, this.createdAtMillis});
  final String requestId, requesterUid, requesterDisplayName, shadowMemberId, shadowDisplayName, status; final int? createdAtMillis;
}
```

**Wrapper signatures:**
```dart
Future<List<UnclaimedShadow>> listUnclaimedShadows({required String inviteCode});
Future<ClaimRequestResult> requestClaimShadow({required String inviteCode, required String shadowMemberId, required String displayName});
Future<ClaimDecisionResult> decideClaimRequest({required String groupId, required String requestId, required bool approve});
Future<List<MyClaimRequest>> listMyClaimRequests({required String inviteCode});
Future<List<GroupClaimRequest>> listGroupClaimRequests({required String groupId});
```
Cast `result.data` defensively: `(result.data['shadows'] as List).map((e) => UnclaimedShadow(shadowMemberId: (e as Map)['shadowMemberId'] as String, displayName: e['displayName'] as String))`. `createdAtMillis` is `num?` → `?.toInt()`.

---

## Provider for the creator surface

```dart
// FutureProvider.family — autoDispose is CORRECT here (opposite of the #104 ledger
// rule): this is watched ONLY on the group-settings screen, never pinned by the
// always-mounted home dashboard, so it disposes when the screen closes. It is NOT
// a balance/ledger provider.
final groupClaimRequestsProvider =
    FutureProvider.autoDispose.family<List<GroupClaimRequest>, String>((ref, groupId) {
  return ref.read(groupServiceProvider).listGroupClaimRequests(groupId: groupId);
});
```
Refreshed via `ref.invalidate(groupClaimRequestsProvider(groupId))` after each approve/decline and on pull-to-refresh.

---

## Join-screen flow (the heart of PR9)

Replace the bare auto-submit-joins behavior with **discover-then-branch**:

1. **Discovery** — when the code reaches a valid 6 chars (auto, or on the Join button), instead of joining immediately, call `listUnclaimedShadows(code)` (discovery is read-only and harmless pre-gate; the durable-credential gate fires before `requestClaimShadow`). Show a small inline spinner during discovery. **(Gate R1 P3 — DO NOT move the existing durable-credential gate (`join_group_screen.dart:111-119`, #441) out of the plain-join branch: the "I'm new"/no-shadow path MUST still hit `durableCredentialGateProvider.ensure(...)` before `joinGroup`. Discovery is additive; the existing gate stays exactly where it is.)**
   - **empty list →** proceed to the EXISTING `_joinGroup()` path unchanged (preserves today's UX for groups with no shadows).
   - **non-empty →** reveal the **claim picker** (do NOT auto-join).
2. **Picker** — `groupClaimPickerTitle` "Is one of these you?" + subtitle; a list of shadow rows (`RAvatar` + name); a trailing **"No, I'm new"** action.
   - **tap a shadow →** the **permanent-confirmation sheet** (D3, below). On affirmative confirm → `requestClaimShadow(inviteCode, shadowMemberId, displayName: <the name field>)` → transition to the **waiting state**.
   - **tap "No, I'm new" →** proceed to the EXISTING `_joinGroup()`. If the typed name collides with a shadow, the unchanged #279 guard throws `already-exists` → `_errorMessage()` maps it; extend that message to the actionable `groupClaimNameTakenClaimInstead` ("That name belongs to someone added earlier. Claim it above, or pick a different name.").
3. **Permanent-confirmation sheet** (D3) — a modal sheet (NOT a default-OK dialog) titled `groupClaimConfirmTitle` "Claim {name}'s spot?", body `groupClaimConfirmWarning` "This permanently merges {name}'s expenses into your account. It can't be undone, and the group creator must approve.", a destructive-styled affirmative button `groupClaimConfirmCta` "Yes, claim {name}'s spot" (key `GroupKeys.claimConfirmButton`) and a Cancel. `requestClaimShadow` fires ONLY after the affirmative tap.
4. **Waiting state** (P9-2) — `groupClaimWaitingTitle` "Waiting for approval" + `groupClaimWaitingBody`; a **"Check again"** button (`GroupKeys.claimCheckAgainButton`) → `listMyClaimRequests(inviteCode)`, find this shadow's request:
   - `status == 'claimed'` → `context.pushReplacement('/group/${groupId}')` (groupId from the `ClaimRequestResult`; the requester is now a member via the engine `arrayUnion`).
   - `status == 'declined'` → show `groupClaimDeclinedBody`, offer "join as new" (back to the form).
   - else (still `pending`) → snackbar `groupClaimStillPending`. Also fetch once on mount.
   > **Gate R1 P3 — the post-approval-crash edge:** if `decideClaimRequest` re-keyed successfully but crashed before writing `status:'claimed'` (`decideClaimRequest.ts:129-133`), the request stays `pending` forever yet the requester IS already a member with the inherited balance (self-correcting false-negative; money correct, label lags). The waiting screen will keep showing "still pending" and never auto-navigate. This is NOT a bug to fix in PR9 — the user reaches the group via the normal group list (they're a member). Do not add a "force navigate on pending" hack; just don't treat a stuck-pending as an error.

> **Navigation guard:** the waiting state is an in-screen state of `JoinGroupScreen`, not a new route — no deep-link/back-guard surface added (CLAUDE.md routing landmine avoided; `app_router.dart` untouched). Back from the waiting state returns to the picker/form.

---

## Creator approve-UI (Group Settings)

In `GroupMembersSection` (or a sibling widget it renders), **creator-only** (`isCurrentUserCreator`), mount a **"Claim requests"** subsection ABOVE the member list:
- `ref.watch(groupClaimRequestsProvider(groupId))` → `.when(...)`:
  - empty → render nothing (or a quiet `groupClaimNoRequests` only if you want it visible; default: hide when empty to avoid clutter).
  - data → one row per pending request: "{requester} wants to claim {shadow}'s spot" (`groupClaimRequestRow`, 2 placeholders) + **Approve** (`GroupKeys.claimApprove(requestId)`) + **Decline** (`GroupKeys.claimDecline(requestId)`).
- **Approve →** `decideClaimRequest(groupId, requestId, approve:true)`:
  - resolves `status:'claimed'` → snackbar `groupClaimApproved` ("{requester} now holds {shadow}'s spot."); `ref.invalidate(groupClaimRequestsProvider(groupId))` + invalidate the members stream so the new member + dropped shadow refresh.
  - throws `failed-precondition` ("already claimed"/"claimer already present") → snackbar with the mapped message; refresh.
  - throws `internal` (RETRYABLE) → snackbar `groupClaimApproveError` "Couldn't complete the claim. Try again." (NEVER show as success).
- **Decline →** `decideClaimRequest(..., approve:false)` → snackbar `groupClaimRequestDeclined`; refresh.
- Wrap each row's buttons in a per-row busy guard so a double-tap can't double-fire (the engine is idempotent, but the UI shouldn't invite it).

> Loading/empty states that land on `EmptyStateView`/`_ErrorView` must `pumpAndSettle()` in tests (CLAUDE.md ticker trap).

---

## l10n keys (EN — add 1:1 to `app_ar.arb`)

| key | EN | placeholders |
|---|---|---|
| `groupClaimPickerTitle` | Is one of these you? | — |
| `groupClaimPickerSubtitle` | Someone added these names before you joined. Claim your spot to inherit your share. | — |
| `groupClaimImNew` | No, I'm new | — |
| `groupClaimConfirmTitle` | Claim {name}'s spot? | name |
| `groupClaimConfirmWarning` | This permanently merges {name}'s expenses into your account. It can't be undone, and the group creator must approve. | name |
| `groupClaimConfirmCta` | Yes, claim {name}'s spot | name |
| `groupClaimWaitingTitle` | Waiting for approval | — |
| `groupClaimWaitingBody` | We sent your request to the group creator. You'll join {name}'s spot once they approve. | name |
| `groupClaimCheckAgain` | Check again | — |
| `groupClaimStillPending` | Still waiting for the creator to approve. | — |
| `groupClaimDeclinedBody` | The creator declined your claim. You can join as a new member instead. | — |
| `groupClaimNameTakenClaimInstead` | That name belongs to someone added earlier. Claim it above, or pick a different name. | — |
| `groupClaimRequestsTitle` | Claim requests | — |
| `groupClaimRequestRow` | {requester} wants to claim {shadow}'s spot | requester, shadow |
| `groupClaimApprove` | Approve | — |
| `groupClaimDecline` | Decline | — |
| `groupClaimApproved` | {requester} now holds {shadow}'s spot. | requester, shadow |
| `groupClaimRequestDeclined` | Request declined. | — |
| `groupClaimApproveError` | Couldn't complete the claim. Try again. | — |
| `groupClaimNoRequests` | No pending claim requests. | — |

Run `flutter gen-l10n` after editing both ARBs; `flutter analyze` must stay clean (`prefer_const_constructors`).

---

## Tasks (TDD, each leaves the tree green)

### Task 9.1 — `listUnclaimedShadows` callable (BACKEND, GATE)
- **Files:** Create `functions/src/callables/listUnclaimedShadows.ts`, `functions/test/callables/listUnclaimedShadows.test.ts`; modify `functions/src/index.ts`.
- **9.1.1 RED** — write `listUnclaimedShadows.test.ts` (table below); run scoped emulator → FAIL (module not found). Commit `test(functions): RED listUnclaimedShadows discovery callable (#278 PR9)`.
- **9.1.2 GREEN** — implement mirroring `listMyClaimRequests.ts`; add the alphabetical re-export. Run scoped emulator → all rows PASS. `npm run build` + `npm run lint` clean. `bash tool/list_expected_functions.sh | grep listUnclaimedShadows`. Commit `feat(functions): listUnclaimedShadows pre-join discovery callable (#278 PR9)`.
- **Test table:**
  ```
  U1. anon caller → permission-denied (D6); no read
  U2. bad/unknown inviteCode → invalid-argument (malformed) / not-found (unknown)
  U3. missing / soft-deleted / deletingInProgress group → not-found
  U4. valid code, NON-MEMBER caller, group with 2 shadows + 1 real member →
      returns EXACTLY the 2 shadows ({shadowMemberId, displayName}); the real member is ABSENT (P9-4)
  U5. a tombstoned shadow (isTombstone:true) and a shadow whose userId ∉ memberIds are BOTH excluded
  U6. a group with no shadows → returns { shadows: [] }
  U7. member caller (already joined) → still returns the shadows (no membership gate, P9-4) — harmless
  ```

### Task 9.2 — Client wrappers + result models
- **Files:** Create `lib/features/groups/models/claim_models.dart`; modify `lib/features/groups/providers/group_provider.dart` (5 wrappers + override seams + `groupClaimRequestsProvider`); Test `test/features/groups/claim_wrappers_test.dart`.
- **9.2.1 RED** — unit test each wrapper via the override seam: asserts the right callable name + payload mapping (use a fake override returning canned data; assert the typed model is parsed). Run `flutter test test/features/groups/claim_wrappers_test.dart` → FAIL.
- **9.2.2 GREEN** — implement the 5 wrappers + models + provider. `flutter analyze` clean. Tests PASS. Commit `feat(groups): typed client wrappers for the claim/merge callables (#278 PR9)`.

### Task 9.3 — l10n EN+AR (BEFORE the UI tasks so they compile)
- **Files:** modify `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`; run `flutter gen-l10n`.
- Add all keys in the table (EN) + Arabic 1:1. `flutter gen-l10n` regenerates `app_localizations.dart`. `flutter analyze` clean. Commit `feat(l10n): claim/merge strings EN+AR (#278 PR9)`.

### Task 9.4 — Join-screen claim picker + permanent-confirm + waiting + "I'm new"
- **Files:** modify `lib/features/groups/screens/join_group_screen.dart` (+ any extracted picker/confirm/waiting widgets under `lib/features/groups/widgets/`); modify `lib/features/groups/keys/...` (new `GroupKeys`); Test `test/features/groups/join_claim_picker_test.dart`.
- **9.4.1 RED** — widget tests (table below) via `_MockGroupService` override; run → FAIL.
- **9.4.2 GREEN** — implement the discover→picker→confirm→waiting flow + "I'm new". `flutter analyze` clean; existing `create_join_group_test.dart` still green (no-shadow path unchanged). Commit `feat(groups): claim picker + permanent-confirm + waiting on join (#278 PR9)`.
- **Widget test table:**
  ```
  J1. code with a claimable shadow → picker shows the shadow name + "No, I'm new" (no auto-join)
  J2. code with NO shadows → existing join path runs (joinGroup called), NO picker (regression guard)
  J3. tap a shadow → permanent-warning sheet shows the EXACT irreversibility copy; requestClaimShadow NOT yet called
  J4. confirm the warning (affirmative tap) → requestClaimShadow(inviteCode, shadowMemberId, name) called once → waiting state shown
  J5. cancel the warning → requestClaimShadow NOT called; back on the picker
  J6. waiting + "Check again" → listMyClaimRequests; status 'claimed' → pushReplacement('/group/<id>')
  J7. waiting + "Check again" → status 'declined' → declined message + join-as-new affordance
  J8. "No, I'm new" → joinGroup called (normal path); a colliding name surfaces groupClaimNameTakenClaimInstead
  ```

### Task 9.5 — Creator approve-UI (Group Settings)
- **Files:** modify `lib/features/groups/widgets/group_members_section.dart` (+ a `ClaimRequestsSection` widget); Test `test/features/groups/claim_requests_section_test.dart`.
- **9.5.1 RED** — widget tests (table below) via `_MockGroupService` + `groupClaimRequestsProvider` override; run → FAIL.
- **9.5.2 GREEN** — implement the creator-only subsection. `flutter analyze` clean; existing `group_members_section_shadow_test.dart` still green. Commit `feat(groups): creator approve/decline UI for claim requests (#278 PR9)`.
- **Widget test table:**
  ```
  C1. non-creator viewer → NO claim-requests section rendered (even with pending requests seeded)
  C2. creator + 1 pending request → row "{requester} wants to claim {shadow}'s spot" + Approve + Decline
  C3. creator + 0 pending → section hidden (or quiet empty per P9-1)
  C4. Approve → decideClaimRequest(groupId, requestId, true); on 'claimed' → success snackbar + provider invalidated
  C5. Decline → decideClaimRequest(..., false); declined snackbar + refresh
  C6. Approve resolves engine 'internal' → "try again" snackbar, NOT a success (retryable, never terminal-success)
  ```

### Task 9.6 — Close-out
- `flutter analyze` clean; FULL `flutter test` green; `flutter test test/unit/release_workflow_gate_test.dart` green; `cd functions && npm run build && npm run lint` clean.
- Update **CLAUDE.md "Name-based members"** invariant: claim/merge is LIVE — a real joiner adopts a shadow via creator-approval; the #279 collision on join now offers a claim instead of dead-ending; `GroupMember.isShadow` now has a claim path. Remove the "adding-friends-by-name is unbuilt (#278)" clause.
- Update `MEMORY.md` index + the PR9 memory file.
- File the **P9-1 follow-up** issue ("creator push notification on claimRequests create").
- Commit `docs: flip Name-based-members invariant — claim/merge LIVE (#278 PR9)`.

---

## Done-criteria PR9 (CLOSES #278)

- [ ] Gate-cleared (no [P1]) on THIS spec BEFORE code.
- [ ] `listUnclaimedShadows` callable + U1–U7 green; `export { … } from` re-export; deploy-drift gate green (`release_workflow_gate_test.dart`).
- [ ] 5 typed client wrappers + result models; wrapper tests green.
- [ ] Join picker + **hard permanent-confirmation (D3, affirmative tap)** + waiting/poll + "I'm new" fallback; J1–J8 green; no-shadow join path unchanged (J2 regression).
- [ ] Creator approve/decline UI; C1–C6 green incl. the `internal`-is-retryable C6.
- [ ] l10n EN+AR for all keys; `flutter gen-l10n` run; `flutter analyze` clean.
- [ ] `firestore.rules` UNTOUCHED; `app_router.dart` UNTOUCHED; the 4 PR8 callables + engine UNTOUCHED; #279 join guard UNTOUCHED.
- [ ] CLAUDE.md "Name-based members" invariant flipped; P9-1 follow-up filed.
- [ ] **`Closes #278` in the PR9 body AND the commit message** (squash auto-closes from the COMMIT message — CLAUDE.md). Prior PRs carried `Refs #278`.
- [ ] After merge: ONE backend deploy ceremony (`deploy-ceremony`) covering the whole pending delta (PR6+PR7+PR8+PR9 callables/rules + any earlier undeployed delta) — `backend-deployed` tag advanced, prod-state PASS. No real users → deploy freely.

---

## Gate callout

**PR9 is Gate-CATEGORY** (new Cloud Function auth surface + client orchestration of irreversible money-inheriting flows). Run `/run-the-gate` (fresh-context Opus, zero session history) against THIS spec BEFORE Task 9.1 code. Apply [P1]s, re-run a NEW subagent each round, stop at no-[P1]s. The Gate should specifically probe: (1) the `listUnclaimedShadows` predicate matches `requestClaimShadow`'s claimable predicate exactly (no claimed/tombstoned/relic shadow leaks as claimable); (2) P9-4 info-disclosure is genuinely invite-code-bounded (no real-member identity leak); (3) the D3 permanent-confirmation truly requires an affirmative tap and `requestClaimShadow` cannot fire on a default/dismiss; (4) the `internal`-engine-error path in the creator UI never reads as success (D9 retryable); (5) D8 — the claim path never calls `joinGroupByInviteCode`, and the waiting→group navigation only fires post-`claimed`; (6) no routing-tree/back-guard regression (waiting is in-screen state, not a route). Then `/automerge` re-Gates the diff (fresh Opus review + independent refuter) at merge.
