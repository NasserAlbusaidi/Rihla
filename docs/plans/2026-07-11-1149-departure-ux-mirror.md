# #1149 — Mirror the #1144 departure policies client-side (PR3) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> Gate history: R1 rubric 2 P1 / 1 P2 / 2 P3; R1 adversary 1 P1 / 1 P2 / 2 P3 (the bucket-aggregate P1 was found independently by both) → v2 applied the union. R2 rubric 0 P1 / 1 P2 / 2 P3; R2 adversary 0 P1 / 0 P2 / 2 P3 — **Gate CLOSED (both P1-clean in the same round)**. This is v3 folding the R2 P2/P3 refinements.

**Goal:** Remove the four raw-`permission-denied` UX cliffs left by the #1144 server enforcement — expense pickers, settle-up pair lists, frozen departed-party expenses, correct-settlement affordance — plus give departure-lock `aborted` retry-inviting copy and stop Sentry-capturing it.

**Architecture:** Pure client mirror. Zero changes to `firestore.rules`, Cloud Functions, `BalanceCalculator` math, routing, or any persisted write payload (the only model change is an INBOUND-only read of a field the client already writes). One new pure helper (`expense_party_policy.dart`) mirrors the rules predicate `expensePartiesAreCurrentMembers` byte-for-byte in Dart; one new pure predicate extends `settlement_correction_affordance.dart`; everything else is threading membership sets into existing widgets and adding explanation strings. Every gate **fails open** when its provider hasn't resolved — rules remain the enforcement boundary; the client only pre-empts known-doomed writes with an explanation, and must never block a write the rules would accept.

**Tech Stack:** Flutter/Riverpod 2.x, mocktail + FakeFirebaseFirestore widget tests, ARB l10n (EN+AR).

**Spec seed:** `docs/plans/2026-07-11-1144-post-departure-ledger-fence.md` §D8. Issue: #1149.

---

## Server ground truth being mirrored (verified against code this session)

**THE TWO MEMBER SETS — the load-bearing distinction of this whole PR (Gate R1 P1):**

| Server set | Definition | Gates | Client mirror |
|---|---|---|---|
| `activeGroupMembers()` | `groupData.get('activeMemberIds', memberIds)` — `security/firestore.rules:442-443`. #1144-R5 field maintained by the callables; **falls back to full `memberIds` on legacy groups where the field is absent.** Excludes deleteAccount tombstone ghosts. | Expense **CREATE** party check (`rules:890`, via `enforceParticipantKeys`); event create roster (`rules:587`) | `group.activeMemberIds ?? group.memberIds` (Task 2 adds the read-path) |
| `groupMembers()` | full `group.memberIds` — includes tombstone ghosts AND unclaimed-shadow uuids; excludes only leave/remove-departed uids | Expense **UPDATE/soft-delete** party checks pre+post (`rules:1008-1009`, `:1040-1041`); event-settlement create parties (`rules:1099-1100`); group-settlement parties (~`:1344`); `correctSettlement.ts:159` / `correctLogicalSettleUp.ts:169` (`failed-precondition`) | `group.memberIds` |

Using full `memberIds` for a CREATE check is a **false-permit**: after any member deletes their account, their tombstone id sits in every event's `participantIds` (deleteAccount swaps uid→tombstoneId there too), so an equal-split create would pass a memberIds-based client check and then be rules-denied against `activeGroupMembers()` — the exact cliff this PR removes. Using a tombstone-stripped set for an UPDATE/settlement check is a **false-block**: ghost history must stay editable/correctable/settleable.

- `security/firestore.rules` `expensePartiesAreCurrentMembers(data, members)` (~L765):
  `payerParticipantId in members && customSplitParticipants hasOnly members && splitDistribution.keys() hasOnly members && (scope=='personal' || (scope=='custom' && custom.size()>0) || (splitMode in ['shares','exact','percent'] && dist.size()>0) || participants().hasOnly(members))` — `members` is whichever set the call site passes (table above).
- **The roster-fallback trap:** an equal-split (`equally`, global/subGroup scope, or custom-with-empty-list) expense's effective party set is the WHOLE `event.participantIds`. Since leave/remove never prune `participantIds` (#1131) and deleteAccount tombstones them, any event with a departed participant **or a ghost participant** permanently rejects new equal-split creates — picker filtering alone cannot fix that path; it needs an explanation + pre-submit block.
- Allocation edits check the predicate on **pre AND post state**, gated behind `affectsExpenseAllocation()` (diff touches `payerParticipantId|amountFils|currency|scope|subGroupId|customSplitParticipants|splitMode|splitDistribution` — `rules:947-959`; note **`payerParticipantId` is in this list**). **Metadata-only edits skip the party bundle entirely.** Soft-delete requires the predicate on **pre-state** (`resource.data`) regardless of the diff.
- Client group-create already writes `'activeMemberIds': [uid]` (`group_provider.dart:211`, pinned by `rules:358`); the `Group` model simply doesn't parse it yet.
- Departed member: **no member doc at all** (hard-deleted). Ghost: doc with `isTombstone: true`, id ∈ `memberIds`, ∉ `activeMemberIds`. Shadow: doc with `isShadow: true`, uuid ∈ BOTH sets. Never key any filter off `isShadow`.
- #1144 error contract: departure-lock contention → `aborted`; settle-up-needed → `failed-precondition`. The two must never share a handler branch.

## Scope exclusions (deliberate — follow-ups, do not bundle)

1. **`create_event_screen.dart:289-297` default-selects tombstone ghosts as participants of a brand-new event — this is a LIVE permission-denied cliff, not a mere product decision** (Gate R1 P2): event create requires `participantIds.hasOnly(activeGroupMembers())` (`rules:587`), so on any post-deleteAccount group the default selection is rules-denied. It is a different surface (event creation, not #1149's four) — **file it as its own P2 issue at PR time; the PR body links it.**
2. `group_members_section.dart:287-299` pre-existing asymmetries: no `Sentry.captureException` anywhere in remove-member, and the outer generic catch interpolates raw `e.toString()` — pre-#1144 debt, separate follow-up.
3. `edit_expense_screen.dart` `canEdit` mirrors only `isEventParticipant`, not `isGroupMember` (#1131-era gap) — out of scope.
4. No row-level lock badge on ledger rows — the banner-on-open covers the ask.
5. No new `SettlementWriteErrorKind` / copy change in `settlement_write_error.dart`: `failed-precondition` is thrown by ≥5 distinct causes in `correctSettlement.ts`; cause can't be distinguished without parsing the English message. The affordance-hide IS the fix; the generic denied snackbar stays as backstop.
6. No change to `BalanceCalculator.calculateOptimalSettlements` or any balance provider — pair filtering happens at the display layer only. R1 (departed ex-payer visible in balances at nonzero net) is a pinned deliberate residual; balances sections stay untouched.

## Fail-open rule (applies to every task)

Any gate reading `groupDetailProvider` / `groupMembersProvider` treats loading/error/null as "don't filter, don't freeze, don't warn" (a null GROUP means skip the gate entirely, not filter-against-empty-set — filtering against an empty set would hide everything). The create-side warning/block additionally must not fire against a possibly-stale derived set: it evaluates ONLY when the group doc is resolved; the picker's extra tombstone-doc tightening additionally requires the members stream resolved (Gate R1 P3). Rules backstop every miss.

---

### Task 1: Pure helper `expensePartiesAreCurrentMembers` (Dart mirror of the rules predicate)

**Files:**
- Create: `lib/features/ledger/utils/expense_party_policy.dart`
- Test: `test/unit/expense_party_policy_test.dart`

**Step 1: Write the failing table-driven test** (money-adjacent policy → table-driven per house rules). Fixture ids: `live`, `otherLive`, `ghostId` (tombstone), `shadowUuid`, `departedUid`. Two sets exercised explicitly: `fullMemberIds = {live, otherLive, ghostId, shadowUuid}` (update/settlement context) and `activeSet = {live, otherLive, shadowUuid}` (create context). Cases (each row states WHICH set it passes as `members`):

| # | members set | scope | splitMode | custom | distKeys | roster | expect |
|---|---|-------|-----------|--------|----------|--------|--------|
| 1 | full | personal | – | [] | [] | has departed | **true** (personal ignores roster) |
| 2 | full | global | equally | [] | [] | all current | true |
| 3 | full | global | equally | [] | [] | has departed | **false** (roster fallback) |
| 4 | full | global | exact | [] | [live,ghost] | has departed | **true** (non-equal mode escapes roster; ghost legal on UPDATE set) |
| 5 | full | global | exact | [] | [live,departed] | all current | **false** (dist key departed) |
| 6 | full | custom | equally | [live,shadow] | [] | has departed | **true** (custom non-empty escapes roster; shadow legal) |
| 7 | full | custom | equally | [live,departed] | [] | all current | **false** (custom departed) |
| 8 | full | custom | equally | [] (empty) | [] | has departed | **false** (custom-empty → roster fallback) |
| 9 | full | global | equally | [] | [] | current, but payer=departed | **false** |
| 10 | full | global | shares | [] | [] (empty dist) | has departed | **false** (empty dist → roster fallback) |
| 11 | **active** | global | exact | [] | [live,ghost] | all active | **false** (ghost illegal on CREATE set — same inputs as #4 flip with the set) |
| 12 | **active** | global | equally | [] | [] | roster has ghost | **false** (post-deleteAccount equal-split create is doomed) |
| 13 | **active** | custom | equally | [live,shadow] | [] | roster has ghost | **true** (shadow ∈ activeSet; custom escapes roster) |

**Step 2:** `flutter test test/unit/expense_party_policy_test.dart` → FAIL (helper doesn't exist).

**Step 3: Implement** — signature mirrors the rules argument-for-argument; the CALLER chooses the set; no Riverpod, no Firestore:

```dart
/// Client mirror of firestore.rules `expensePartiesAreCurrentMembers` (~L765).
/// [members] is whichever set the mirrored rules call site passes:
///  - CREATE checks → the ACTIVE set (`group.activeMemberIds ?? group.memberIds`,
///    mirroring rules `activeGroupMembers()` incl. its legacy fallback — rules:890)
///  - UPDATE / soft-delete checks → FULL `group.memberIds` (rules:1008,1041) so
///    ghost history stays editable.
/// Passing the wrong set is a correctness bug in BOTH directions: full-on-create
/// false-permits a doomed write; active-on-update false-blocks ghost history.
bool expensePartiesAreCurrentMembers({
  required String payerParticipantId,
  required ExpenseScope scope,
  SplitMode? splitMode,
  List<String>? customSplitParticipants,
  Iterable<String>? splitDistributionKeys,
  required List<String> eventParticipantIds,
  required Set<String> members,
}) {
  final custom = customSplitParticipants ?? const [];
  final dist = splitDistributionKeys?.toList() ?? const <String>[];
  return members.contains(payerParticipantId) &&
      custom.every(members.contains) &&
      dist.every(members.contains) &&
      (scope == ExpenseScope.personal ||
          (scope == ExpenseScope.custom && custom.isNotEmpty) ||
          (const {SplitMode.shares, SplitMode.exact, SplitMode.percent}
                  .contains(splitMode) &&
              dist.isNotEmpty) ||
          eventParticipantIds.every(members.contains));
}

/// Convenience over a stored [Expense] + its [Event] roster (pre-state check
/// for the R6 freeze / soft-delete mirror — always the FULL memberIds set).
bool expenseReferencesOnlyCurrentMembers(
    Expense expense, List<String> eventParticipantIds, Set<String> memberIds) { ... }
```

(Use the real enum names from `expense_model.dart:8-12` / `split_mode.dart:6`; `subGroup` is the legacy scope and takes the roster branch like global.)

**Step 4:** test → PASS. **Step 5:** `git commit -m "feat(#1149): client mirror of expensePartiesAreCurrentMembers (pure helper)"`

### Task 2: `Group.activeMemberIds` read-path (INBOUND only)

**Files:**
- Modify: `lib/features/groups/models/group_model.dart`
- Test: extend the existing Group model/parse test (locate `group_model` tests; add cases)

**Step 1 (RED):** parse test — doc WITH `activeMemberIds: [a]` → field `[a]`; doc WITHOUT → field null; and an accessor test `activeMemberIdSet`: with field → `{a}`, without → full memberIds set (the rules fallback, ghosts included).

**Step 3:** add `final List<String>? activeMemberIds;` parsed in `fromDoc` (same defensive list-parse style as `memberIds`), plus:
```dart
/// Mirror of rules `activeGroupMembers()` (firestore.rules:442-443) INCLUDING
/// its legacy fallback: absent field → full memberIds (ghosts included). Use
/// for CREATE-side party checks only; update/settlement checks use memberIds.
Set<String> get activeMemberIdSet => (activeMemberIds ?? memberIds).toSet();
```
**Write path untouched:** the group-create write map already carries `activeMemberIds` (`group_provider.dart:211`); the model has NO Firestore write serialization (only the dead-SQLite `toMap` + `copyWith`) — do not add one.

**Step 5:** commit `feat(#1149): parse group.activeMemberIds (INBOUND mirror of activeGroupMembers)`.

### Task 3: Settlement-party predicate

**Files:**
- Modify: `lib/features/ledger/utils/settlement_correction_affordance.dart`
- Test: `test/unit/settlement_correction_affordance_test.dart` (extend)

**Step 1 (RED):** cases — both parties live → true; ghost payer (id ∈ memberIds) → true; departed recipient → false; null payer id → false.

**Step 3:**
```dart
/// #1149 client mirror of correctSettlement.ts / correctLogicalSettleUp.ts
/// current-party check: both parties must be in FULL group.memberIds (ghosts
/// and shadows ARE in memberIds — exact set-membership only, nothing fancier;
/// NEVER the active set here, ghost debt cleanup stays live).
bool settlementPartiesAreCurrentMembers(Settlement s, Set<String> memberIds) {
  final payer = s.payerParticipantId;
  final recipient = s.recipientParticipantId;
  return payer != null && recipient != null &&
      memberIds.contains(payer) && memberIds.contains(recipient);
}
```
**Step 5:** commit `feat(#1149): settlementPartiesAreCurrentMembers predicate`.

### Task 4: l10n strings (EN+AR) + surface test block

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`
- Modify: `test/unit/generated_l10n_surface_test.dart` (new `group('#1149 …')` block — the file does NOT auto-enumerate; keys must be spot-checked explicitly, asserting non-empty + AR≠EN)

Keys (final copy at implementation; keep the intent; none carry a count → no ICU plural risk):
1. `editorDepartedFrozenBanner` — "Someone in this expense left the group, so its amount and split are locked. Details like the description and category can still be edited."
2. `editorPartiesNotCurrentWarning` — "A former member is part of this split. Equal splits aren't available on this event — choose who's included with an exact, shares, or percent split, or record it as a personal expense." (R2-adversary P3: the exact/shares/percent remedy is unreachable in a group shrunk to one member; the personal-scope escape must be named.)
3. `settleUpDepartedPairsHidden` — takes `{count}`: "{count} suggestion(s) involving former members are hidden — those transfers can no longer be recorded." (R2-adversary P3: the headline shows the UNPRUNED count, so the note must carry the number that reconciles headline-vs-tiles. No ICU plural gymnastics required — a simple placeholder form acceptable in both EN/AR is fine.)
4. `groupMembershipChangeInProgress` — "Another membership change is happening right now. Please try again in a moment."

Steps: add EN+AR pairs (genuine AR translations) with `@key.description` documenting the trigger; regenerate l10n; RED surface-test block first → implement → PASS → commit `feat(#1149): l10n for departure-mirror UX (EN+AR)`.

### Task 5: `aborted` handling in leave + remove handlers

**Files:**
- Modify: `lib/features/groups/widgets/group_danger_section.dart` (`_executeLeave` only — `_executeDelete` untouched; deleteGroup doesn't throw `aborted` per the #1144 contract)
- Modify: `lib/features/groups/widgets/group_members_section.dart` (`_handleRemove`)
- Test: `test/features/groups/group_settings_screen_test.dart` (update the pinned aborted test ~L1072-1115), `test/features/groups/group_delete_callable_test.dart` (NEW leave-side aborted test — none exists today)

**Step 1 (RED):** update the pinned remove-member test to expect the NEW copy (`groupMembershipChangeInProgress`) instead of `'Failed to remove Bob: Something went wrong. Please try again.'`, keeping its existing assertion that NO Settle-up `SnackBarAction` renders. Add the parallel leave-side test (`FirebaseFunctionsException(code: 'aborted')` → new copy, no settle action, no navigation).

**Step 3 (implement):** in both handlers, insert **before** the generic branch, mirroring the `failed-precondition` shape:
```dart
// #1144/#1149: departure-lock contention is transient by design — retry-
// inviting copy, never the settle-up snackbar, and never Sentry (expected
// contention, not a defect).
if (e.code == 'aborted') {
  messenger.showSnackBar(
    SnackBar(content: Text(context.l10n.groupMembershipChangeInProgress)),
  );
  return;
}
```
In `_executeLeave` this placement inherently removes `aborted` from the `Sentry.captureException(e)` at the generic branch — that removal is the issue's explicit ask. `not-found` (idempotent success) and `failed-precondition` (settle-up snackbar) branches are untouched.

**Step 4:** run both test files → PASS. **Step 5:** commit `fix(#1149): aborted departure-lock contention gets retry copy, skips Sentry`.

### Task 6: Surface (b)+(d) — settle-up pair filter + correction-affordance hide (single param, shared chokepoint)

**Files:**
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart`
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (group already watched ~L213)
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (group already in scope ~L110-134)
- Test: new `test/features/groups/settle_up_departed_parties_test.dart` (+ extend `test/unit/` for the pure filter fn)

**Design:** one new param `Set<String>? currentMemberIds` on `SettleUpPageBody` (null = unknown → no filtering, no hiding: fail-open). Both screens pass `group?.memberIds.toSet()` — the FULL set (settlement legality), never the active set.

**PRUNE SCOPE IS EXACTLY TWO CONSUMERS (Gate R1 P1, found by both reviewers):** `bucket.optimalSettlements` feeds FOUR user-facing quantities — `totalTransfers` (~L256-259) → `allSettled` (~L261) → `AllSettledState` (~L297) and `settleUpTransfersHeadline` (~L327/459); `totalPending` (~L283-286) → `GroupSettlementSummaryCard` (~L290); the tile loop (~L300-307); and `steppedSettlePairs` (~L262). Prune ONLY the last two. `totalTransfers`, `allSettled`, the headline, `totalPending`, the summary card, and `bucket.balances` ALL keep reading the ORIGINAL buckets — a departed party at nonzero net is real unsettleable money (R1 residual); pruning it out of the aggregates would render "All settled!" over a nonzero balance row (false money-state claim). The hidden-count note is what explains the tile-vs-headline gap.

Inside the body:
1. **Pure top-level fn** (unit-testable next to `steppedSettlePairs`): `filterDepartedSuggestions(List<Map<String, dynamic>> optimalSettlements, Set<String>? currentMemberIds)` → returns (kept, hiddenCount), dropping pairs where `settlement['fromUserId']` or `['toUserId']` ∉ set; null set → input unchanged, 0 hidden. Applied per bucket at the tile loop and to the bucket list handed to `steppedSettlePairs` (build stepped input from pruned copies WITHOUT rebinding the aggregate reads above).
2. Hidden count > 0 → one muted explanatory line (`settleUpDepartedPairsHidden(count)`) rendered in the transfers area — **placed OUTSIDE the `optimalSettlements.isNotEmpty` guard** so it still renders when a bucket's suggestions are FULLY pruned (Gate R1 P3). Needs `// textMuted-decorative-justified:` comment if using `.textMuted`; run `tool/check_theme_purity.sh` locally.
3. **Correction hide (d):** plumbing per R2-rubric P3 — do NOT add a `_HistoryTile` param. For SOLO rows fold the check into the PARENT's wiring: `onCorrect: (_canCorrect(s) && _partiesCurrent(s)) ? onCorrect : null` at the `_HistoryTile` construction sites (~L750/L770); for LOGICAL rows AND `_partiesCurrent(row.representative)` into the existing ternary (~L789-792; every leg of a decomposed set shares one pair, so the representative check is complete). `_partiesCurrent` = `currentMemberIds == null || settlementPartiesAreCurrentMembers(s, currentMemberIds)` (fail-open). The existing in-tile gate (~L1156-1163: `groupSettleUpId == null && !soloCorrectionHidden`) is untouched — a nulled `onCorrect` already collapses it.
4. `preSelectedMemberId` deep-link pointing at a now-pruned tile becomes a silent no-op (~L381-383) — acceptable; leave a one-line code comment (Gate R1 P3).

**RED tests first:**
- unit: `filterDepartedSuggestions` — departed pair pruned, ghost pair kept, null set → unchanged.
- widget (new file, fixture group whose `memberIds` EXCLUDES `departedUid` but INCLUDES `ghostId`): departed pair tile absent + hidden-note present; ghost pair tile present; **NO `AllSettledState` and the summary/headline still reflect the original counts when the only suggestion is a departed pair** (adapt the `settle_up_page_body_former_member_test.dart` fixture: former member owed 20.000 as sole transfer → tile hidden, note shown, balances row still shows 20.000, no "All settled"); correct button absent on a departed-party history settlement, present on a ghost-party one. **Do not mutate the shared `_group()` fixture in `group_settle_up_correct_test.dart`** — its whole file pins `memberIds: ['uid-alice','uid-bob']`; new scenarios get their own fixtures.
- Existing green tests must stay green: all current fixtures use in-membership parties.

Commit `feat(#1149): hide departed-party settle suggestions and correction affordances`.

### Task 7: Surface (a) — expense picker filtering + roster-trap warning/block

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart`
- Modify: `lib/features/ledger/widgets/expense_editor/payer_picker_sheet.dart`
- Modify: `lib/features/ledger/widgets/split_scope_selector.dart` (`CustomParticipantSelector`)
- Test: extend `test/features/ledger/expense_editor_paid_by_picker_test.dart`, `test/features/ledger/custom_split_sheet_test.dart`, `test/features/ledger/add_expense_screen_test.dart`

**Design — computed once in `_ExpenseEditorBodyState`** (it's a `ConsumerStatefulWidget`; already reads `groupMembersProvider` for `isShadow` and watches `eventDetailProvider` at ~L952). TWO distinct artifacts, both derived from the CREATE-side active set (Gate R1 P1 — never full memberIds here):

```dart
/// CREATE-side legality set: exact mirror of rules activeGroupMembers()
/// including the legacy fallback. null → group unresolved → fail open.
Set<String>? _activeSet() =>
    ref.watch(groupDetailProvider(widget.groupId)).valueOrNull?.activeMemberIdSet;

/// Picker candidates: event participants ∩ activeSet, additionally dropping
/// any isTombstone member doc (belt-and-braces for legacy groups whose
/// absent activeMemberIds falls back to memberIds — a "Deleted member" row
/// is never a useful NEW-expense candidate; skipped when members unresolved).
/// null → don't filter. Empty after filtering → null (degenerate, unfiltered).
Set<String>? _eligiblePickerIds(Event event) { ... }
```

**Retention rule:** at each picker call site, the candidate set passed down is `eligible ∪ {ids currently selected on the form}` — an edit that legitimately names a ghost (rules-legal on the UPDATE set) must keep its current selection visible and re-selectable; a filter must never strand form state.

Wire-up (candidate lists only — never the SplitCard equal-split PREVIEW, which is money display):
- `PayerPickerSheet`: new optional `Set<String>? eligibleIds` (null → all `event.participantIds`, preserving today's behavior and existing direct-construction tests); the loop at ~L75 filters. Caller `_openPayerSheet` passes `eligible + current selection`.
- `CustomParticipantSelector` (`split_scope_selector.dart` `_eventParticipants` ~L21-35): same optional param, `eligible + currently-selected custom ids`.
- `_openSplitModeSheet` (~L806-830): filter `ids` to `eligible + ids already carrying a value in the current distribution` before building `SplitParticipant`s.

**Roster-trap warning + pre-submit block:** the picker filter cannot save an equal-split create on an event whose roster holds a departed OR ghost participant (roster fallback vs the ACTIVE set). In the body:
- Compute `partiesOk = expensePartiesAreCurrentMembers(payer/scope/mode/custom/distKeys from CURRENT form state, event.participantIds, members: _activeSet())` — the EXACT mirror set only, never the tombstone-tightened picker set (a block must never fire where rules would pass). Skip (treat as ok) when group/event unresolved, when mode is edit AND the form's allocation fields are unchanged from `widget.initial` (metadata-only edits must never evaluate the party predicate — mirrors the rules diff gate), or when Task 8's frozen state already blocks.
- **Edit-mode allocation changes are checked against the UPDATE semantics, not the create set:** rules run the party bundle with `groupMembers()` on update — so in edit mode `partiesOk` uses FULL `memberIds`, in add mode the ACTIVE set. (One boolean, set chosen by `_isEdit`.)
- `!partiesOk` → inline warning near the split card (`editorPartiesNotCurrentWarning`, styled after the `settle_scope_note.dart` pinned Icon+Text pattern, directional APIs only) AND `_submit` shows the same copy as a snackbar and returns WITHOUT attempting the write.

**RED tests:**
- payer picker: departed participant absent; ghost absent; ghost retained when it is the current selection; `eligibleIds: null` → unchanged full list (pins fail-open).
- custom selector: same trio.
- add-expense flow: event `[me, departedUid]`, group memberIds `[me]` → equally-mode shows the warning; tapping save shows the block snackbar and writes nothing; switching to exact among `[me]` clears the warning.
- add-expense post-deleteAccount flow (Gate R1 P1 regression pin): event `[me, ghostId]`, group `memberIds [me, ghostId]`, `activeMemberIds [me]` → equally-mode create shows the warning and blocks; exact among `[me]` passes.

Commit `feat(#1149): filter expense pickers to active members; block roster-trap equal splits with explanation`.

### Task 8: Surface (c) — R6 frozen-expense explanation in the editor

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart`
- Modify: `lib/features/ledger/widgets/expense_editor/delete_card.dart` (only if a prop is missing — it already takes `enabled`)
- Test: extend `test/features/ledger/edit_expense_screen_test.dart`

**Design:** in edit mode, frozen = `widget.initial != null && event != null && group != null && !expenseReferencesOnlyCurrentMembers(widget.initial!, event.participantIds, group.memberIds)` — computed from the STORED expense (pre-state, matching the rules' soft-delete gate) against **FULL memberIds** (ghost-party history is NOT frozen), fail-open on any unresolved provider. NOT a full-screen `_ErrorScaffold` (that would over-block: metadata edits are rules-legal on frozen expenses).

Effects when frozen:
1. Banner at the top of the form (`editorDepartedFrozenBanner`, same visual pattern as Task 7's warning; render at the OfflineBanner slot ~L993 or after `ExpenseProvenanceByline` ~L1038).
2. `DeleteCard` `enabled: !_isSubmitting && !frozen` (soft-delete is rules-blocked on pre-state).
3. `_submit`: allocation-affecting change attempted while frozen → show `editorDepartedFrozenBanner` copy as snackbar, don't write. Metadata-only diffs proceed normally (rules allow). **Detecting "allocation-affecting" = `moneyDirty || payerDirty` — BOTH existing flags (`expense_editor_body.dart:462-483`), composed** (Gate R1 P2 + R2-rubric P2): `moneyDirty` alone EXCLUDES the payer (payer-only edit would slip to a generic rules denial); a hand-rolled all-fields comparison alone re-introduces the #1092 scope-mask false-dirty (`moneyDirty` compares `customSplitParticipants` only when `scope == custom` on purpose — an unconditional comparison would false-block a metadata-only edit after a scope round-trip, violating "never block a write rules would accept").
4. Ghost-party expense (payer = tombstone id): NOT frozen (ghost ∈ memberIds) — pin with a test.

**RED tests (fixture: expense whose payer is `departedUid`, group memberIds without it):** banner visible; delete button disabled; editing only the description saves successfully (calls `onSubmit`); changing the amount then saving shows the frozen snackbar and does NOT call the update service; **changing ONLY the payer then saving is blocked with the frozen copy (the `moneyDirty` trap pin)**; ghost-payer expense shows no banner and delete stays enabled. Equal-split expense on a departed-participant event (payer still live) IS frozen — the roster branch — pin one test on exactly that.

Commit `feat(#1149): frozen departed-party expenses get a read-only explanation, delete disabled, metadata edits stay open`.

### Task 9: Full verification + PR

1. `flutter analyze` → clean.
2. `flutter test` → full suite green.
3. `bash tool/check_theme_purity.sh` → clean (new banner/note widgets).
4. Review full branch diff `git diff main...HEAD` — confirm zero hits under `functions/`, `security/`, `lib/core/router/`; the only model diff is `group_model.dart` READ-path (`activeMemberIds` parse + accessor, no write serialization); `expense_provider.dart` untouched; `settle_up_page_body.dart` shows display helpers only.
5. File the follow-up issues: (i) create-event ghost default-selection is rules-denied post-deleteAccount (`rules:587`) — P2; (ii) remove-member Sentry/`e.toString()` gaps.
6. PR: `Closes #1149`, body links the follow-up issues, `Spec:` line pointing at this file. `/automerge`.

---

## Verification principles applied (results)

1. **Callsite classification:** every touched surface is INBOUND/display or a pre-write UX gate; no OUTBOUND write payload is modified anywhere. `Group.activeMemberIds` is added to the READ path only — the write map at `group_provider.dart:211` predates this PR (#1154). The pair filter prunes suggestion DISPLAY; aggregates (`totalTransfers`/`totalPending`/`allSettled`/headline/summary/balances) deliberately keep reading unpruned buckets.
2. **Concrete claims re-verified in-session:** rules predicate (~L765), `activeGroupMembers()` (L442-443), create-gate `activeGroupMembers()` (L890), event-create roster (L587), `affectsExpenseAllocation` field list incl. payer (~L947-959), update/soft-delete gates on `groupMembers()` (~L1008-1041), settlement create gates on `groupMembers()` (~L1099-1100), client write of `activeMemberIds` (`group_provider.dart:211`) and its absence from `Group` model (`group_model.dart`), `ExpenseEditorBody extends ConsumerStatefulWidget` (L133) + `initial: expense` + `eventDetailProvider` watch (~L952), `PayerPickerSheet(event:, selectedPayerId:)` call site (~L756), solo-correct render gate (~L1156-1163), logical ternary (~L789-792), `steppedSettlePairs` scanning `bucket.optimalSettlements` independently (~L76-78), leave/remove `failed-precondition` branches + Sentry sites, `Settlement.payerParticipantId/recipientParticipantId` nullable (settlement_model.dart:8-9).
3. **Read-path per write-path:** no write paths change. The pre-submit blocks only ever REFUSE a write the rules would refuse, because each block evaluates the EXACT mirror set of its rules call site (create → active, update → full) and fails open on unresolved providers. The picker filter may be TIGHTER than rules (tombstone-tightening on legacy groups) — legal because a picker narrows candidates, never blocks a write.
4. **Fields enumerated from types:** Expense party fields = `payerParticipantId` (single String — there is no payers map), `customSplitParticipants` (List?, persisted `[]` when unused — an empty list is NOT a zero-way split), `splitDistribution` (Map?), `scope`, `splitMode`. Settlement = nullable `payerParticipantId`/`recipientParticipantId`. Group gains `activeMemberIds` (List<String>?, read-only).
5. **Data contracts spelled out:** `SettleUpPageBody.currentMemberIds: Set<String>?` (null = fail-open; always FULL memberIds); `PayerPickerSheet.eligibleIds: Set<String>?` (null = unfiltered); `filterDepartedSuggestions` consumes optimalSettlements map keys `fromUserId`/`toUserId` (Strings) and returns (kept, hiddenCount); `Group.activeMemberIdSet` = `(activeMemberIds ?? memberIds).toSet()`.
6. **Arithmetic decomposition:** the one decomposition touched is DISPLAY-side: transfer tiles are a subset of the aggregates after pruning, BY DESIGN, with the hidden-note as the reconciling explanation. Aggregates themselves stay computed from unpruned buckets, so no displayed money quantity changes value.
7. **Orthogonal-axis worked examples:**
   - *Identity axis:* group `{alice, ghost-deleted-abc12345, shadowUuid}` (`activeMemberIds {alice, shadowUuid}`), departed `bob` still in `event.participantIds`. Expense E1 equally-split global (payer alice) is FROZEN (roster branch, full-set check catches bob) though bob isn't payer or a dist key. New-expense pickers offer `{alice, shadowUuid}` (ghost excluded — active set; bob excluded — departed; shadow retained). New equal-split create is BLOCKED with explanation on ghost-roster events too (active-set roster check). Settle-up: alice↔bob suggestion hidden + note; alice↔ghost suggestion visible and recordable; ghost-party history keeps Correct; alice↔bob history hides Correct.
   - *Money-display axis (Gate R1):* former member owed 20.000 as the sole suggestion → tile hidden, note shown, headline/summary/balances unchanged, NO "All settled".
