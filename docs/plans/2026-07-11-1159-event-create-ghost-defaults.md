# #1159 — Create-event stops default-selecting deleteAccount ghosts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> Gate history: R1 rubric 0 P1 / 1 P2 / 2 P3; R1 adversary 0 P1 / 0 P2 / 1 P3 — **Gate CLOSED round 1 (both P1-clean)**. This is v2 folding the P2/P3 refinements (Test-3 discriminator, Test-6 RED wording, departure-lock scope clause).

**Goal:** On any group where a member has deleted their account, `CreateEventScreen`'s DEFAULT participant selection includes the tombstone ghost and is therefore rules-denied (`participantIds.hasOnly(activeGroupMembers())`, `security/firestore.rules:565`) — the same raw permission-denied cliff class #1149 removed for expenses/settlements, on the event-create surface. Fix: filter the picker candidates and the default selection to active (non-tombstone) members, exactly mirroring the rules gate. (Scope is the GHOST cliff only: the same create branch also conjoins `groupAllowsClientWrites()` — the departure/quiesce lock, `rules:564` — whose transient denial during a `departureInProgress` window is a separate cliff, deliberately NOT mirrored here.)

**Architecture:** Pure client change, one screen. Zero changes to `firestore.rules`, Cloud Functions, `BalanceCalculator`, routing, models, or l10n. `CreateEventScreen` computes an eligible-members list (non-tombstone docs ∩ `group.activeMemberIdSet` when the group doc is resolved — the #1149 Task-7 convention verbatim) and uses it for the picker rows, Select-All, the default selection, AND the submitted `participantIds` (stateless intersection at render/submit, which also closes the members-resolve-before-group race). `EventParticipantsCard` stays purely presentational and untouched. Fail-open everywhere: unresolved group doc → skip the active-set filter; rules remain the enforcement boundary.

**Tech Stack:** Flutter/Riverpod 2.x, mocktail widget tests, existing fixtures in `test/features/events/create_event_test.dart`.

**DEPENDS ON #1161 (must be merged first):** `Group.activeMemberIds` + `Group.activeMemberIdSet` land with PR #1161 (#1149 Task 2). Branch from `main` only after #1161 merges; `grep -n "activeMemberIdSet" lib/features/groups/models/group_model.dart` must hit before starting.

**Spec seed:** #1149 Gate R1 rubric P2 → filed as #1159. Issue: #1159.

---

## Server ground truth being mirrored (verified against code this session)

- **Event create roster gate** (`security/firestore.rules:565`, in `validEventCreate`'s standard branch): `request.resource.data.participantIds.hasOnly(activeGroupMembers())`. `activeGroupMembers()` (`rules:420-422`) = `groupData.get('activeMemberIds', memberIds)` — #1144 R5 field, **falls back to full `memberIds` (ghosts included) on legacy groups where the field is absent**.
- The founding-batch branch (`rules:568-571`, #874) covers only the #245 seeded event riding the group-create batch — participants collapse to exactly `[creator]`; no ghost surface there (brand-new group). Verified: `group_provider.dart` seeds `participantIds: [uid]`.
- **`create_event_screen.dart` is the ONLY client writer of event `participantIds`** (verified: `stageEvent` callers = `create_event_screen.dart` + the group-create seed in `group_provider.dart`; `event_info_section.dart`'s `updateEvent` is metadata-only — name/dates/description; no client surface edits an existing event's roster).
- The bug, concretely (`create_event_screen.dart:289-300`): on first members-stream data, `_selectedParticipantIds = members.map((m) => m.userId).toSet()` — every `groupMembersProvider` doc, including `isTombstone` ghosts. `EventParticipantsCard` then renders the ghost as a selectable "(former member)" row (`MemberNameResolver` suffix) and Select-All re-selects it.
- Identity taxonomy (#1149 table, unchanged): **ghost** = member doc with `isTombstone: true`, tombstoneId ∈ `memberIds`, ∉ `activeMemberIds`. **Shadow** = `isShadow: true`, uuid ∈ BOTH sets — must stay selectable and default-selected; never key any filter off `isShadow`. **Departed** (leave/remove) = no member doc at all — can never appear in this picker. `activeMemberIds` = `memberIds` minus tombstone ids by construction (`nextActiveMemberIds`), so the ONLY ids the active-set filter can drop are tombstones.
- `Group.activeMemberIdSet` (from #1161) = `(activeMemberIds ?? memberIds).toSet()` — the exact rules mirror INCLUDING the legacy fallback.

## Decisions (the issue's open questions, resolved)

1. **Ghost rows are HIDDEN, not disabled-with-explanation.** Matches the #1149 payer-picker/custom-selector precedent (silent candidate filter). A "Former member" row in a NEW-event picker serves no purpose: rules deny selecting it on current groups, and on legacy groups (absent `activeMemberIds`, where rules would technically accept it) default-rostering a deleted user mints fresh equal-split exposure — the exact thing #1144 R5 closed. No aggregate on this screen references member counts, so hiding leaves no headline-vs-rows gap to reconcile (the reason #1149's settle-up surface needed a note does not exist here). **Zero l10n changes.**
2. **Belt-and-braces tombstone-doc drop applies even when the active-set filter can't run** (legacy fallback or unresolved group doc) — same rationale as #1149 Task 7's `_eligiblePickerIds`. Tighter-than-rules is legal for a picker: it narrows candidates, never blocks a write.
3. **Fail-open:** group doc loading/error/null → skip the active-set filter (members docs are by construction resolved — we're inside `membersAsync.when(data:)`). Degenerate guard: if filtering empties the list, fall back to the unfiltered list (can't happen in practice — the viewer is a live member — but never render an empty picker because of a filter).
4. **Stateless selection pruning at render + submit** (not re-`setState`): `_selectedParticipantIds` is initialized ONCE, so if the members stream resolves before the group doc, a malformed ghost doc (`isTombstone` field absent/wrong-typed → salvaged `false`) could enter the initial selection and only later become ineligible when the group resolves. Intersecting the stored selection with the eligible-id set at every build (for the card) and at submit (for the write) makes the rendered state and the write self-consistent with the tightest currently-known set, without setState-in-build.

## Scope exclusions (deliberate)

1. `EventParticipantsCard` untouched — stays presentational; its `isFormer` disambiguation branch becomes unreachable from this screen (harmless; the resolver is generic and the card has no group doc to filter against).
2. No pre-submit warning/block copy (the #1149 roster-trap pattern) — unlike expenses, there is no roster-fallback trap here: the filter fully determines the write's key set, so a filtered selection cannot be rules-denied on the party gate. Rules backstop the fail-open windows.
3. Event UPDATE roster surfaces — none exist client-side (verified above); the light/admin ADD-delta rules gates (`rules:648/651`) have no client UI to mirror.
4. `group_members_section.dart` roster display of ghosts, expense pickers, settle-up — #1149's surfaces, already shipped in #1161.

## Fail-open rule (applies to every task)

Identical to #1149: unresolved `groupDetailProvider` → don't apply the active-set filter (never filter-against-empty-set); the tombstone-doc drop still applies because member docs are resolved. The filter may be tighter than rules (legacy-group tombstones); it must never be looser where the group doc is resolved.

---

### Task 1: RED widget tests — new file `test/features/events/create_event_ghost_participants_1159_test.dart`

**Files:**
- Create: `test/features/events/create_event_ghost_participants_1159_test.dart`

Model the harness on `create_event_test.dart` (`_wrapCreate` / `_wrapCreateRouted`, `sharedPreferencesProvider` override in `setUpAll`, timer-free `ConnectivityNotifier(startPeriodicChecks: false)`, mocked `EventService`/`GroupActivityService` for submit capture). Do NOT mutate `create_event_test.dart`'s shared fixtures — new file, own fixtures.

**Fixtures:**

```dart
const _tombId = 'tombstone-deleted-abc123';
final _live = GroupMember(id: 'uid-a', groupId: 'g1', userId: 'uid-a',
    displayName: 'Alice', role: 'CREATOR', joinedAt: DateTime(2026));
final _liveB = GroupMember(id: 'uid-b', groupId: 'g1', userId: 'uid-b',
    displayName: 'Bob', role: 'MEMBER', joinedAt: DateTime(2026));
final _shadow = GroupMember(id: 'shadow-uuid-1', groupId: 'g1', userId: 'shadow-uuid-1',
    displayName: 'Chad', role: 'MEMBER', isShadow: true, joinedAt: DateTime(2026));
final _ghost = GroupMember(id: _tombId, groupId: 'g1', userId: _tombId,
    displayName: 'Dana', role: 'MEMBER', isTombstone: true, joinedAt: DateTime(2026));

final _groupR5 = Group(   // post-#1154 group: field present
  id: 'g1', name: 'G', inviteCode: 'ABC123', createdBy: 'uid-a',
  memberIds: ['uid-a', 'uid-b', 'shadow-uuid-1', _tombId],
  activeMemberIds: ['uid-a', 'uid-b', 'shadow-uuid-1'],
  createdAt: DateTime(2026));
final _groupLegacy = _groupR5.copyWith();   // then null the field — copyWith
  // can't null it (?? pattern); construct a second literal WITHOUT activeMemberIds.
```

**Tests (each named for what it pins):**

1. `ghost row hidden, live+shadow rows shown` — pump with `[_live, _liveB, _shadow, _ghost]` + `_groupR5`; expect `find.text('Dana')` nothing, `find.text('Alice')`/`'Bob'`/`'Chad'` one each.
2. `default selection excludes ghost — submitted participantIds are active-only` — routed harness with mocked `EventService`; fill name, tap create; capture `stageEvent` and assert `participantIds` set == `{uid-a, uid-b, shadow-uuid-1}` and `participantNames` has no `_tombId` key.
3. `Select All checked at default AND only eligible rows render` — Gate R1-rubric P2: a bare checkbox-checked assertion is NON-discriminating (pre-fix: selection 4 == rendered 4 → also checked). Must pair the discriminator: assert the `EventKeys.selectAllButton` checkbox `value == true` **AND exactly 3 participant rows render (Dana's row absent)** after first pump-and-settle — the row count is what goes RED pre-fix.
4. `Select All selects only eligible members` — uncheck all, tap Select-All, submit → captured `participantIds` == active-only set.
5. `legacy group (no activeMemberIds): tombstone doc still hidden` — `_groupLegacy` + `_ghost` → 'Dana' absent (belt-and-braces pin).
6. `fail-open: group doc never resolves → non-tombstone members shown and default-selected` — override `groupDetailProvider('g1')` with a never-emitting stream; expect Alice/Bob/Chad rows present, Dana absent (tombstone drop is member-doc-only), and — via submit capture with the routed harness — `participantIds` == `{uid-a, uid-b, shadow-uuid-1}`.
7. `late group resolve prunes a stale initial selection (the race pin)` — member doc `userId: 'not-active'` with `isTombstone: false` (models the malformed-ghost salvage), group via `StreamController`: first pump WITHOUT a group emission (row visible, default-selected), then emit `_groupR5`-style group whose `activeMemberIds` excludes `'not-active'`; expect the row disappears AND submit excludes `'not-active'`.
8. `degenerate: filtering would empty the list → unfiltered fallback` — members `[_ghost]` only + `_groupR5` → Dana row IS shown (never an empty picker from a filter).

**Run:** `flutter test test/features/events/create_event_ghost_participants_1159_test.dart` → expect FAIL on 1–5, 7, 8. Test 6 also fails pre-fix on TWO clauses (Gate R1-rubric P3): the Dana-row-absent assertion AND the submit-capture assertion (pre-fix `participantIds` would carry all 4 ids).

**Commit:** `test(#1159): RED — create-event ghost default-selection pins`

### Task 2: Implement the eligibility filter in `CreateEventScreen`

**Files:**
- Modify: `lib/features/events/screens/create_event_screen.dart` (the `data:` callback ~L287-342 and `_submitForm` ~L115-134)

**Step 1 — eligible list + pruned selection, computed in the `data:` callback** (the screen already watches `groupDetailProvider(widget.groupId)` for the header name — reuse that watch, hoist it to a `Group?` local instead of `.valueOrNull?.name` inline):

```dart
// #1159: event create is gated on participantIds.hasOnly(activeGroupMembers())
// (rules:565) — never offer or default-select a candidate that gate would
// deny. Eligible = non-tombstone docs ∩ activeMemberIdSet (exact rules mirror
// incl. legacy fallback; #1149 convention). Group unresolved → tombstone drop
// only (fail-open). Filter-emptied → unfiltered (degenerate, viewer is live).
final active = group?.activeMemberIdSet;
var eligible = members
    .where((m) =>
        !m.isTombstone && (active == null || active.contains(m.userId)))
    .toList();
if (eligible.isEmpty) eligible = members;
final eligibleIds = {for (final m in eligible) m.userId};
// Stateless prune: the one-shot initial selection may predate the group doc
// (or a later roster change); intersecting here keeps render + write
// consistent with the tightest known set without setState-in-build.
final selection =
    Set<String>.unmodifiable(_selectedParticipantIds.intersection(eligibleIds));
```

**Step 2 — wire it through:**
- Initial population (~L293-295): `members.map((m) => m.userId)` → `eligibleIds` (guard stays `members.isNotEmpty`).
- `EventParticipantsCard(members: eligible, selectedIds: selection, ...)` — onToggle/onSelectAllChanged unchanged (they can only ever add eligible ids since only eligible rows render).
- `LoadingButton.onPressed: () => _submitForm(eligible)`.
- `_submitForm(List<GroupMember> members)`: first line, prune the state the same way — `final selected = _selectedParticipantIds.intersection({for (final m in members) m.userId});` — then use `selected` for the empty-check, `participantNames`, and `participantIds` (replacing every `_selectedParticipantIds` read in the method). The "select at least one participant" snackbar now also covers a selection emptied by pruning.

**Step 3:** `flutter test test/features/events/create_event_ghost_participants_1159_test.dart` → PASS (all 8).

**Step 4:** `flutter test test/features/events/` → existing suites green (their fixtures are tombstone-free; test 3's checked-by-default semantics already held for them).

**Step 5 — Commit:** `fix(#1159): create-event picker and default selection mirror activeGroupMembers — no ghost participants`

### Task 3: Full verification + PR

1. `flutter analyze` → clean.
2. `flutter test` → full suite green. (`tool/check_theme_purity.sh` — nothing new styled, but run it; it's cheap.)
3. Branch diff `git diff main...HEAD`: exactly one lib file (`create_event_screen.dart`) + one new test file + this plan. Zero hits under `functions/`, `security/`, `lib/core/router/`, `**/models/`.
4. PR: `Closes #1159`, `Refs #1149 #1144`, `Spec:` line pointing at this file, RED-first evidence pasted (Task 1 failing output). `/automerge`.

---

## Verification principles applied (results)

1. **Callsite classification:** the touched path is OUTBOUND (`_selectedParticipantIds` feeds `stageEvent(participantIds:)` — a persisted write and a balance-universe input). That is exactly why the filter must be the EXACT rules mirror or tighter, never looser: dropping a live/shadow member would silently shrink every equal split's universe on the new event. The filter can only drop ids ∉ `activeMemberIdSet` ∪ tombstone-docs — by `nextActiveMemberIds` construction, only tombstones.
2. **Concrete claims re-verified in-session:** rules create gate (`firestore.rules:565`), `activeGroupMembers()` w/ fallback (`:420-422`), founding-batch branch (`:568-571`), the default-select-all bug (`create_event_screen.dart:289-300`), `EventParticipantsCard` rendering ghosts as selectable rows (isFormer suffix, `event_participants_card.dart:40-46`), sole-writer claim (`grep -rln stageEvent lib/` → create screen + group-create seed; `event_info_section.dart` updateEvent has no participant params), seeded event = `[uid]` (`group_provider.dart:239-244`), `GroupMember.isTombstone` salvage semantics (`group_member_model.dart:55`), `Group.activeMemberIdSet` on the #1161 branch (`group_model.dart:138`), client write of `activeMemberIds` at group create (`group_provider.dart:211`).
3. **Read-path per write-path:** the write is `events/{eid}.participantIds`; its enforcing reader is `validEventCreate` (rules:565) and its balance reader is the per-event universe (`participantIds ∪ payers+settlement parties`). The change only ever REMOVES rules-denied (or product-doomed legacy-tombstone) keys from the write — it cannot introduce a key.
4. **Fields enumerated from the type:** `GroupMember` = id/groupId/userId/displayName/role/isShadow/isTombstone/joinedAt — the filter keys on `isTombstone` + `userId` only; `isShadow` deliberately untouched (spec'd in Decisions). `Group.activeMemberIdSet` = `(activeMemberIds ?? memberIds).toSet()`.
5. **Data contracts spelled out:** `EventParticipantsCard.members: List<GroupMember>` (now the eligible subset), `selectedIds: Set<String>` (now the pruned intersection); `_submitForm(List<GroupMember>)` receives the SAME eligible list the card rendered (WYSIWYG — what's on screen is what's written); `stageEvent(participantIds: List<String>, participantNames: Map<String,String>)` keys ⊆ eligibleIds.
6. **Arithmetic decomposition:** none — no money quantity is computed or displayed on this screen; the participant set feeds FUTURE splits, covered by (1).
7. **Orthogonal-axis worked example (identity × time):** group `{alice, bob, shadowUuid, tomb-dana}`, `activeMemberIds {alice, bob, shadowUuid}`. Cold-open create-event offline (group doc from cache — resolved): picker shows Alice/Bob/Chad, default-selects all three, Dana hidden; submit queues `participantIds [alice,bob,shadowUuid]` which replays cleanly on reconnect (pre-fix: replay is silently discarded at rules — the #929-class offline discard, on this surface). Same group where Dana deleted her account pre-#1154 (legacy, no `activeMemberIds`): rules would ACCEPT Dana, filter still hides her (belt-and-braces) — deliberate tighter-than-rules, a picker narrowing. Shadow Chad stays selectable in every scenario (uuid ∈ active set).
