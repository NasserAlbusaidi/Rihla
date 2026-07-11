# #1149 — Mirror the #1144 departure policies client-side (PR3) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the four raw-`permission-denied` UX cliffs left by the #1144 server enforcement — expense pickers, settle-up pair lists, frozen departed-party expenses, correct-settlement affordance — plus give departure-lock `aborted` retry-inviting copy and stop Sentry-capturing it.

**Architecture:** Pure client mirror. Zero changes to `firestore.rules`, Cloud Functions, `BalanceCalculator` math, routing, or any persisted schema. One new pure helper (`expense_party_policy.dart`) mirrors the rules predicate `expensePartiesAreCurrentMembers` byte-for-byte in Dart; one new pure predicate extends `settlement_correction_affordance.dart`; everything else is threading `group.memberIds` / tombstone sets into existing widgets and adding two explanation strings. Every gate **fails open** when its provider hasn't resolved — rules remain the enforcement boundary; the client only pre-empts known-doomed writes with an explanation.

**Tech Stack:** Flutter/Riverpod 2.x, mocktail + FakeFirebaseFirestore widget tests, ARB l10n (EN+AR).

**Spec seed:** `docs/plans/2026-07-11-1144-post-departure-ledger-fence.md` §D8. Issue: #1149.

---

## Server ground truth being mirrored (verified against code this session)

- `security/firestore.rules` `expensePartiesAreCurrentMembers(data, members)` (~L765):
  `payerParticipantId in members && customSplitParticipants hasOnly members && splitDistribution.keys() hasOnly members && (scope=='personal' || (scope=='custom' && custom.size()>0) || (splitMode in ['shares','exact','percent'] && dist.size()>0) || participants().hasOnly(members))` — where `members` = `group.memberIds`.
- **The roster-fallback trap:** an equal-split (`equally`, global/subGroup scope, or custom-with-empty-list) expense's effective party set is the WHOLE `event.participantIds`. Since leave/remove never prune `participantIds` (#1131), any event with a departed participant **permanently rejects new equal-split creates** — picker filtering alone cannot fix that path; it needs an explanation + pre-submit block.
- Allocation edits check the predicate on **pre AND post state**, gated behind `affectsExpenseAllocation()` (diff touches `payerParticipantId|amountFils|currency|scope|subGroupId|customSplitParticipants|splitMode|splitDistribution`). **Metadata-only edits skip the party bundle entirely.** Soft-delete requires the predicate on **pre-state** (`resource.data`) regardless of the diff.
- Settlements: `validEventSettlementCreate` and `validGroupSettlementBase` require both `payerParticipantId`/`recipientParticipantId` ∈ `group.memberIds`. `correctSettlement.ts` (~L159) / `correctLogicalSettleUp.ts` (~L169) throw `failed-precondition` when either party ∉ `memberIds`.
- **Membership sets — the load-bearing distinction:**
  - `group.memberIds` (write-legality set): INCLUDES deleteAccount tombstone ghosts (`deleted-<sha1(uid)[:8]>` swapped in by `deleteAccount.ts:723`) and unclaimed-shadow uuids; EXCLUDES only leave/remove-departed uids. Ghosts stay settleable/correctable/nameable-on-edit.
  - "R5 picker set" (new-expense candidates): `memberIds` minus tombstones — ghosts are rules-legal on new expenses but product policy (issue #1149 / residual R5) keeps them out of NEW-expense pickers.
  - A departed member has **no member doc at all** (hard-deleted); a ghost has a doc with `isTombstone: true`; a shadow has a doc with `isShadow: true`. Never key any filter off `isShadow`.
- #1144 error contract: departure-lock contention → `aborted`; settle-up-needed → `failed-precondition`. The two must never share a handler branch.

## Scope exclusions (deliberate — follow-ups, do not bundle)

1. `create_event_screen.dart:289-297` default-selects tombstone ghosts as participants of a brand-new event — product decision, file as its own issue.
2. `group_members_section.dart:287-299` pre-existing asymmetries: no `Sentry.captureException` anywhere in remove-member, and the outer generic catch interpolates raw `e.toString()` — pre-#1144 debt, separate follow-up.
3. `edit_expense_screen.dart` `canEdit` mirrors only `isEventParticipant`, not `isGroupMember` (#1131-era gap) — out of scope.
4. No row-level lock badge on ledger rows — the banner-on-open covers the ask.
5. No new `SettlementWriteErrorKind` / copy change in `settlement_write_error.dart`: `failed-precondition` is thrown by ≥5 distinct causes in `correctSettlement.ts`; cause can't be distinguished without parsing the English message. The affordance-hide IS the fix; the generic denied snackbar stays as backstop.
6. No change to `BalanceCalculator.calculateOptimalSettlements` or any balance provider — pair filtering happens at the display layer only. R1 (departed ex-payer visible in balances at nonzero net) is a pinned deliberate residual; balances sections stay untouched.

## Fail-open rule (applies to every task)

Any gate reading `groupDetailProvider` / `groupMembersProvider` treats loading/error/null as "don't filter, don't freeze, don't warn" (mirror the `_shadowUserIds` pattern: `.valueOrNull ?? const []` → but a null GROUP means skip the gate entirely, not filter-against-empty-set — filtering against an empty set would hide everything). Rules backstop every miss.

---

### Task 1: Pure helper `expensePartiesAreCurrentMembers` (Dart mirror of the rules predicate)

**Files:**
- Create: `lib/features/ledger/utils/expense_party_policy.dart`
- Test: `test/unit/expense_party_policy_test.dart`

**Step 1: Write the failing table-driven test** (money-adjacent policy → table-driven per house rules). Cases, each asserting against `memberIds = {payer live, ghostId (tombstone, IN memberIds), shadowUuid (IN memberIds), otherLive}` and `eventParticipantIds` that may include `departedUid` (NOT in memberIds):

| # | scope | splitMode | custom | distKeys | roster has departed? | expect |
|---|-------|-----------|--------|----------|----------------------|--------|
| 1 | personal | – | [] | [] | yes | **true** (personal ignores roster) |
| 2 | global | equally | [] | [] | no | true |
| 3 | global | equally | [] | [] | yes | **false** (roster fallback) |
| 4 | global | exact | [] | [live,ghost] | yes | **true** (non-equal mode escapes roster; ghost ∈ memberIds) |
| 5 | global | exact | [] | [live,departed] | no | **false** (dist key departed) |
| 6 | custom | equally | [live,shadow] | [] | yes | **true** (custom non-empty escapes roster; shadow legal) |
| 7 | custom | equally | [live,departed] | [] | no | **false** (custom departed) |
| 8 | custom | equally | [] (empty) | [] | yes | **false** (custom-empty → roster fallback) |
| 9 | global | equally | [] | [] | no, but **payer departed** | **false** |
| 10 | global | shares | [] | [] (empty dist) | yes | **false** (empty dist → roster fallback) |

**Step 2:** `flutter test test/unit/expense_party_policy_test.dart` → FAIL (helper doesn't exist).

**Step 3: Implement** — signature mirrors the rules argument-for-argument; no Riverpod, no Firestore:

```dart
/// Client mirror of firestore.rules `expensePartiesAreCurrentMembers` (~L765).
/// `memberIds` is group.memberIds — includes tombstone ghosts and shadows,
/// excludes leave/remove-departed uids. NEVER pass a tombstone-stripped set.
bool expensePartiesAreCurrentMembers({
  required String payerParticipantId,
  required ExpenseScope scope,
  SplitMode? splitMode,
  List<String>? customSplitParticipants,
  Iterable<String>? splitDistributionKeys,
  required List<String> eventParticipantIds,
  required Set<String> memberIds,
}) {
  final custom = customSplitParticipants ?? const [];
  final dist = splitDistributionKeys?.toList() ?? const <String>[];
  return memberIds.contains(payerParticipantId) &&
      custom.every(memberIds.contains) &&
      dist.every(memberIds.contains) &&
      (scope == ExpenseScope.personal ||
          (scope == ExpenseScope.custom && custom.isNotEmpty) ||
          (const {SplitMode.shares, SplitMode.exact, SplitMode.percent}
                  .contains(splitMode) &&
              dist.isNotEmpty) ||
          eventParticipantIds.every(memberIds.contains));
}

/// Convenience over a stored [Expense] + its [Event] roster (pre-state check
/// for the R6 freeze / soft-delete mirror).
bool expenseReferencesOnlyCurrentMembers(
    Expense expense, List<String> eventParticipantIds, Set<String> memberIds) { ... }
```

(Use the real enum names from `expense_model.dart` — verify `ExpenseScope`/`SplitMode` member spellings at implementation time; `subGroup` is the legacy scope and takes the roster branch like global.)

**Step 4:** test → PASS. **Step 5:** `git commit -m "feat(#1149): client mirror of expensePartiesAreCurrentMembers (pure helper)"`

### Task 2: Settlement-party predicate

**Files:**
- Modify: `lib/features/ledger/utils/settlement_correction_affordance.dart`
- Test: `test/unit/settlement_correction_affordance_test.dart` (extend)

**Step 1 (RED):** cases — both parties live → true; ghost payer (id ∈ memberIds) → true; departed recipient → false; null payer id → false.

**Step 2-4:**
```dart
/// #1149 client mirror of correctSettlement.ts / correctLogicalSettleUp.ts
/// current-party check: both parties must be in group.memberIds (ghosts and
/// shadows ARE in memberIds — exact set-membership only, nothing fancier).
bool settlementPartiesAreCurrentMembers(Settlement s, Set<String> memberIds) {
  final payer = s.payerParticipantId;
  final recipient = s.recipientParticipantId;
  return payer != null && recipient != null &&
      memberIds.contains(payer) && memberIds.contains(recipient);
}
```
**Step 5:** commit `feat(#1149): settlementPartiesAreCurrentMembers predicate`.

### Task 3: l10n strings (EN+AR) + surface test block

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`
- Modify: `test/unit/generated_l10n_surface_test.dart` (new `group('#1149 …')` block — the file does NOT auto-enumerate; keys must be spot-checked explicitly, asserting non-empty + AR≠EN)

Keys (final copy at implementation; keep the intent):
1. `editorDepartedFrozenBanner` — "Someone in this expense left the group, so its amount and split are locked. Details like the description and category can still be edited."
2. `editorPartiesNotCurrentWarning` — "A former member is part of this split. Equal splits aren't available on this event — choose who's included with an exact, shares, or percent split."
3. `settleUpDepartedPairsHidden` — "Suggestions involving former members are hidden — those transfers can no longer be recorded."
4. `groupMembershipChangeInProgress` — "Another membership change is happening right now. Please try again in a moment."

Steps: add EN+AR pairs with `@key.description` documenting the trigger; regenerate l10n; RED surface-test block first (asserting the new keys) → implement → PASS → commit `feat(#1149): l10n for departure-mirror UX (EN+AR)`.

### Task 4: `aborted` handling in leave + remove handlers

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

### Task 5: Surface (b)+(d) — settle-up pair filter + correction-affordance hide (single param, shared chokepoint)

**Files:**
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart`
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (group already watched ~L213)
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (group already in scope ~L110-134)
- Test: new `test/features/groups/settle_up_departed_parties_test.dart` (+ extend `test/unit/` for the pure filter fn)

**Design:** one new param `Set<String>? currentMemberIds` on `SettleUpPageBody` (null = unknown → no filtering, no hiding: fail-open). Both screens pass `group?.memberIds.toSet()` (null when group unresolved).

Inside the body:
1. **Pure top-level fn** (unit-testable next to `steppedSettlePairs`): `filterDepartedSuggestions(List<SettleBucket> buckets, Set<String>? currentMemberIds)` → prunes each bucket's `optimalSettlements` of pairs where `settlement['fromUserId']` or `['toUserId']` ∉ set; returns pruned buckets + total hidden count. Null set → input unchanged, 0 hidden.
2. `build()` applies it ONCE, and the pruned buckets feed BOTH the transfer-tile loop (~L300-307) AND `steppedSettlePairs` (~L262) — the stepped cards must not leak a filtered pair. `bucket.balances` is NOT touched (R1 display stays warn-not-block).
3. Hidden count > 0 → one muted explanatory line (`settleUpDepartedPairsHidden`) rendered in the transfers area (needs `// textMuted-decorative-justified:` comment if using `.textMuted` — theme-purity check is CI-only, run `tool/check_theme_purity.sh` locally).
4. **Correction hide (d):** AND `settlementPartiesAreCurrentMembers(settlement, currentMemberIds)` into the solo-button render gate (~L1156-1163, composing with — not replacing — the existing `groupSettleUpId == null && !soloCorrectionHidden` logic) and into the logical row's ternary (~L789-792, checking `row.representative`; every leg of a decomposed set shares one pair, so the representative check is complete). When `currentMemberIds == null` → treat as current (fail-open).

**RED tests first:**
- unit: `filterDepartedSuggestions` — departed pair pruned, ghost pair kept, null set → unchanged.
- widget (new file, fixture group whose `memberIds` EXCLUDES `departedUid` but INCLUDES `ghostId`): departed pair tile absent + hidden-note present; ghost pair tile present; correct button absent on a departed-party history settlement, present on a ghost-party one. **Do not mutate the shared `_group()` fixture in `group_settle_up_correct_test.dart`** — its whole file pins `memberIds: ['uid-alice','uid-bob']`; new scenarios get their own fixtures.
- Existing green tests must stay green: all current fixtures use in-membership parties.

Commit `feat(#1149): hide departed-party settle suggestions and correction affordances`.

### Task 6: Surface (a) — expense picker filtering + roster-trap warning/block

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart`
- Modify: `lib/features/ledger/widgets/expense_editor/payer_picker_sheet.dart`
- Modify: `lib/features/ledger/widgets/split_scope_selector.dart` (`CustomParticipantSelector`)
- Test: extend `test/features/ledger/expense_editor_paid_by_picker_test.dart`, `test/features/ledger/custom_split_sheet_test.dart`, `test/features/ledger/add_expense_screen_test.dart`

**Design — computed once in `_ExpenseEditorBodyState`** (it's a `ConsumerStatefulWidget`; already reads `groupMembersProvider` for `isShadow` and watches `eventDetailProvider` at ~L952):

```dart
/// R5 picker set: event participants who are in group.memberIds and not
/// tombstoned. Ghosts are rules-legal parties but stay out of NEW-expense
/// pickers (residual R5); departed ids are absent from memberIds entirely.
/// null when the group doc hasn't resolved → callers must not filter.
Set<String>? _eligiblePickerIds(Event event) {
  final group = ref.watch(groupDetailProvider(widget.groupId)).valueOrNull;
  if (group == null) return null;                      // fail-open
  final members = ref.watch(groupMembersProvider(widget.groupId)).valueOrNull;
  final tombstones = {
    for (final m in members ?? const <GroupMember>[])
      if (m.isTombstone) m.userId,
  };
  final memberIds = group.memberIds.toSet();
  final eligible = {
    for (final id in event.participantIds)
      if (memberIds.contains(id) && !tombstones.contains(id)) id,
  };
  return eligible.isEmpty ? null : eligible;           // degenerate → unfiltered
}
```

**Retention rule:** at each picker call site, the candidate set passed down is `eligible ∪ {ids currently selected on the form}` — an edit that legitimately names a ghost (rules-legal) must keep its current selection visible and re-selectable; a filter must never strand form state.

Wire-up (candidate lists only — never the SplitCard equal-split PREVIEW, which is money display):
- `PayerPickerSheet`: new optional `Set<String>? eligibleIds` (null → all `event.participantIds`, preserving today's behavior and existing direct-construction tests); the loop at ~L75 filters. Caller `_openPayerSheet` passes `eligible + current selection`.
- `CustomParticipantSelector` (`split_scope_selector.dart` `_eventParticipants` ~L21-35): same optional param, `eligible + currently-selected custom ids`.
- `_openSplitModeSheet` (~L806-830): filter `ids` to `eligible + ids already carrying a value in the current distribution` before building `SplitParticipant`s.

**Roster-trap warning + pre-submit block:** the picker filter cannot save an equal-split create on a departed-participant event (roster fallback). In the body:
- Compute `partiesOk = expensePartiesAreCurrentMembers(payer/scope/mode/custom/distKeys from CURRENT form state, event.participantIds, group.memberIds)` — skip (treat as ok) when group/event unresolved, when mode is edit AND the form's allocation fields are unchanged from `widget.initial` (metadata-only edits must never evaluate the party predicate — mirrors the rules diff gate), or when Task 7's frozen state already blocks.
- `!partiesOk` → inline warning near the split card (`editorPartiesNotCurrentWarning`, styled after the `settle_scope_note.dart` pinned Icon+Text pattern, directional APIs only) AND `_submit` shows the same copy as a snackbar and returns WITHOUT attempting the write.

**RED tests:**
- payer picker: departed participant absent; ghost absent; ghost retained when it is the current selection; `eligibleIds: null` → unchanged full list (pins fail-open).
- custom selector: same trio.
- add-expense flow: event `[me, departedUid]`, group memberIds `[me]` → equally-mode shows the warning; tapping save shows the block snackbar and writes nothing; switching to exact among `[me]` clears the warning.

Commit `feat(#1149): filter expense pickers to current non-tombstone members; block roster-trap equal splits with explanation`.

### Task 7: Surface (c) — R6 frozen-expense explanation in the editor

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart`
- Modify: `lib/features/ledger/widgets/expense_editor/delete_card.dart` (only if a prop is missing — it already takes `enabled`)
- Test: extend `test/features/ledger/edit_expense_screen_test.dart`

**Design:** in edit mode, frozen = `widget.initial != null && event != null && group != null && !expenseReferencesOnlyCurrentMembers(widget.initial!, event.participantIds, group.memberIds)` — computed from the STORED expense (pre-state, matching the rules' soft-delete gate), fail-open on any unresolved provider. NOT a full-screen `_ErrorScaffold` (that would over-block: metadata edits are rules-legal on frozen expenses).

Effects when frozen:
1. Banner at the top of the form (`editorDepartedFrozenBanner`, same visual pattern as Task 6's warning; render at the OfflineBanner slot ~L993 or after `ExpenseProvenanceByline` ~L1038).
2. `DeleteCard` `enabled: !_isSubmitting && !frozen` (soft-delete is rules-blocked on pre-state).
3. `_submit`: allocation-affecting change attempted while frozen → show `editorDepartedFrozenBanner` copy as snackbar, don't write. Metadata-only diffs proceed normally (rules allow). Detecting "allocation-affecting" = compare form state against `widget.initial` on the same 8 fields the rules diff-gate lists (currency is edit-immutable already; `subGroupId` legacy — compare defensively).
4. Ghost-party expense (payer = tombstone id): NOT frozen (ghost ∈ memberIds) — pin with a test.

**RED tests (fixture: expense whose payer is `departedUid`, group memberIds without it):** banner visible; delete button disabled; editing only the description saves successfully (calls `onSubmit`); changing the amount then saving shows the frozen snackbar and does NOT call the update service; ghost-payer expense shows no banner and delete stays enabled. Equal-split expense on a departed-participant event (payer still live) IS frozen — the roster branch — pin one test on exactly that.

Commit `feat(#1149): frozen departed-party expenses get a read-only explanation, delete disabled, metadata edits stay open`.

### Task 8: Full verification + PR

1. `flutter analyze` → clean.
2. `flutter test` → full suite green.
3. `bash tool/check_theme_purity.sh` → clean (new banner/note widgets).
4. Review full branch diff `git diff main...HEAD` — confirm zero hits under `functions/`, `security/`, `lib/core/router/`, model `toFirestore`/`fromDoc` bodies, `expense_provider.dart` mutation paths (only `settle_up_page_body.dart`'s display helpers should appear).
5. PR: `Closes #1149`, body lists the follow-ups from Scope exclusions (ghost default-selection on create-event → new issue; remove-member Sentry/`e.toString()` gaps → new issue or note). `Spec:` line pointing at this file. `/automerge`.

---

## Verification principles applied (results)

1. **Callsite classification:** every touched surface is INBOUND/display or a pre-write UX gate; no OUTBOUND write payload is modified anywhere. The pair filter prunes suggestions before display; it never alters `SettleBucket.balances`, `optimalSettlements` construction inputs, or any write body.
2. **Concrete claims re-verified in-session:** rules predicate text (~L765), `affectsExpenseAllocation` field list (~L947), update/soft-delete gates (~L1000-1043), `ExpenseEditorBody extends ConsumerStatefulWidget` (L133) + `initial: expense` (full stored object) + `eventDetailProvider` watch (~L952), `PayerPickerSheet(event:, selectedPayerId:)` call site (~L756), solo-correct render gate (~L1156-1163), logical ternary (~L789-792), `steppedSettlePairs` scanning `bucket.optimalSettlements` independently (~L76-78), leave/remove `failed-precondition` branches + Sentry sites, `Settlement.payerParticipantId/recipientParticipantId` nullable (settlement_model.dart:8-9).
3. **Read-path per write-path:** no write paths change. The one behavioral write-adjacent change (pre-submit blocks) only ever REFUSES a write the rules would refuse; a false-positive block is impossible when providers are unresolved (fail-open) and otherwise exactly mirrors the rules predicate proven by Task 1's table.
4. **Fields enumerated from types:** Expense party fields = `payerParticipantId` (single String — there is no payers map), `customSplitParticipants` (List?, persisted `[]` when unused — an empty list is NOT a zero-way split), `splitDistribution` (Map?), `scope`, `splitMode`. Settlement = nullable `payerParticipantId`/`recipientParticipantId`.
5. **Data contracts spelled out:** `SettleUpPageBody.currentMemberIds: Set<String>?` (null = fail-open); `PayerPickerSheet.eligibleIds: Set<String>?` (null = unfiltered); optimalSettlements map keys consumed: `fromUserId`, `toUserId` (Strings), as used by `steppedSettlePairs` today.
6. **Arithmetic decomposition:** n/a — no money math changes; the only numeric surfaces (equal-split preview, bucket balances) are deliberately NOT filtered, precisely to avoid changing displayed money.
7. **Orthogonal-axis worked example (identity axis, the trap axis for this change):** group `{alice, ghost-deleted-abc12345, shadowUuid}`, departed `bob` still in `event.participantIds`, expense E1 equally-split global on that event (payer alice). E1 is FROZEN (roster branch) though bob isn't payer or a dist key — Task 7 pins this. New-expense pickers offer `{alice, shadowUuid}` (ghost excluded R5, bob excluded departed, shadow retained). Settle-up: alice↔bob suggestion hidden + note shown; alice↔ghost suggestion visible and recordable; ghost-party history row keeps Correct; alice↔bob history row (pre-departure settlement) hides Correct — server would `failed-precondition` it.
