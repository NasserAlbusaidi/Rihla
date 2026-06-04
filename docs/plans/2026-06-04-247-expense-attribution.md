# #247 — expense attribution over-restricted (payer leader-gated; can't include self; preview lies)

**Branch:** `fix/issue-247-expense-attribution`
**Touches:** split **preview math / display** + the persisted `customSplitParticipants` write payload → **Gate before code.** Client-only — **no rules change** (verified §below). Money-relevant: the preview≠persisted divergence is a silently-wrong-money bug.
**UX decision (locked):** custom scope **pre-selects the current user** (deselectable).

## 1. Three root causes, verified against `main`

1. **Payer picker leader-gated** — `split_scope_selector.dart:360-363`: `isLeader = currentUid != null && event.createdBy == currentUid; if (!isLeader || participants.isEmpty) return SizedBox.shrink();`. A non-leader can't attribute payment to anyone but themselves.
2. **Custom picker excludes self** — `split_scope_selector.dart:233-235`: `participants.where((p) => p.id != currentUid)`. You can only tick *others*; you can never put yourself into a custom split.
3. **Preview ≠ persisted ("preview lies", money-wrong)** — the displayed split inserts the payer:
   - editor `_splitParticipantIds` `expense_editor_body.dart:379-380`: `final p = _selectedPayerId; if (p != null && !ids.contains(p)) ids.insert(0, p);`
   - preview card `_SplitPreviewCard._splitParticipantIds` `expense_editor_body.dart:1031`: `if (payerId != null && !ids.contains(payerId)) ids.insert(0, payerId!);`
   …but persistence stores `customSplitParticipants` **verbatim** (`_submit:215-217` → service) and `BalanceCalculator` splits over exactly that set (no payer insertion). So the editor can show "2 ways · X/2 each" while the ledger records the **full amount on one person**.

**Live-wiring confirmed:** `SplitScopeSelector` (hosting `_PayerSelector` + `_CustomParticipantSelector`) is rendered inside `_SplitCustomiseSheet` at `expense_editor_body.dart:1662`; the sheet is opened from `_openCustomiseSheet:291`. These are the live widgets, not a dead parallel.

## 2. Rules already permit the correct model — NO rules change (verified against `security/firestore.rules`)
- `:470` `function participants()` — the valid set (event participantIds).
- `:550` `data.payerParticipantId in participants()` — payer is any participant, **NOT** tied to creator/leader.
- `:556` `data.customSplitParticipants.hasOnly(participants())` — any subset, **including** the creator.
- `:480` `splitDistribution.keys().hasOnly(participants())`.
So the leader-gate and self-exclusion are **purely client-side**. Rules untouched. (CLAUDE.md warns rules validate shape not value — but here membership IS validated, and it already allows the target behavior.)

## 3. Fix (client only)
1. **Ungate the payer dropdown** — `split_scope_selector.dart:362`: drop `!isLeader ||` → `if (participants.isEmpty) return SizedBox.shrink();`. Keep the `isMe` "(me)" labeling (`:397`). Any creator can now set any participant as payer (rules already allow, `:550`).
2. **Include current user in the custom picker** — `split_scope_selector.dart:233-235`: drop the `.where((p) => p.id != currentUid)` filter; list ALL `participants`. Also retarget the empty-state guard `:237-240` from `otherParticipants.isEmpty` → `participants.isEmpty` and the `ListView` source `:244-248` from `otherParticipants` → `participants`. **No "(me)" affordance in the custom tile** (Gate R2 P3): `_ParticipantTile:277-341` has none, and `isMe`/`editorParticipantMe` is wired ONLY in `_PayerSelector:397` — the current-user row shows its name pre-checked like any other; adding a "(me)" badge to the custom list is out-of-scope (§6). `editorNoOtherParticipants` ("No other participants…") becomes reachable only with zero participants (degenerate — an event always has its creator) — leave the string, rename deferred (§6).
3. **Pre-select the current user on entering custom scope** — when scope changes to `custom` and the custom set is empty, seed it with the **participant-resolved current-user id**. (Gate R1 P2):
   - Source the id from `currentEventParticipantProvider((groupId, eventId))?.id` (the same identity used at `_submit:190-197` / `trip_provider.dart:13-21`), **NOT** raw `currentUserProvider?.uid` — a non-participant uid would violate `firestore.rules customSplitParticipants.hasOnly(participants())`.
   - `_SplitCustomiseSheet` is a bare `StatefulWidget` (`:1545`, no `ref`), so **pass `currentParticipantId` in as a constructor arg** from `_openCustomiseSheet` (the editor has `ref`). Seed inside the sheet's `onScopeChanged` handler **guarded on `_custom.isEmpty`**, so custom→global→custom (or an edit of an existing `{him}`-only expense) does NOT re-seed / duplicate self. Deselectable. (Money-correct default: "I paid, split me+him" → tick "him" → 2-way → him owes half.)
   - **Null guard (Gate R2 P3):** if `currentParticipantId` is null (viewer not in `participantIds` — `currentEventParticipantProvider` returns null, `trip_provider.dart:19`), **skip seeding** — never add `null` to `_custom`. The picker still lists everyone; the viewer just starts with an empty custom set (→ preview falls back to global per Fix #4, which is correct).
4. **Preview = persisted set, mirroring the calculator's empty→global fallback** — remove the payer-auto-insert from BOTH `_splitParticipantIds`, and mirror the calculator so preview == ledger **even when the custom set is empty** (Gate R1 P1):
   - editor `:379-381` (custom branch) → `_customSplitParticipants.isEmpty ? event.participantIds : _customSplitParticipants.toList()`
   - preview card `:1029-1032` (custom branch) → `customSplitParticipants.isEmpty ? event.participantIds : customSplitParticipants.toList()`
   This matches `BalanceCalculator`'s custom-scope behavior exactly (`expense_provider.dart:219-225`: empty `customSplitParticipants` → global split over all participants). Without this mirror, a deselect-all custom set previews as "no split / tap to customise" while the ledger silently splits globally — the very preview-lie #247 kills, surviving at the empty edge. "Paid by" stays a separate display (`_PaidByCard`). Result: preview == ledger for **every** scope including empty-custom.
5. Keep the empty-custom → global fallback in `BalanceCalculator` as-is (`expense_provider.dart:219-225`) — **no calculator change**; `balance_calculations_test.dart` stays green. (NOTE: this is the ONLY "stays green" claim — the selector widget tests do NOT; see §5.)

## 4. Verification principles
1. **Callsite classification of the split-participant set:**
   - `_SplitPreviewCard` (`:1025`) → **INBOUND** display. Today it lies (inserts payer); fix makes it truthful.
   - editor `_splitParticipantIds` (`:372`) feeds: the split-mode sheet's exact/shares/percent entry list (`:337`) → builds `splitDistribution` → **OUTBOUND write**; and the `< 2` action gate (`:478-487`). After the fix it equals `customSplitParticipants` — so the advanced-split entry operates over exactly the persisted set (correct).
   - `_submit` persists `customSplitParticipants` verbatim (`:215-217`) → **OUTBOUND**. Unchanged by this fix (already verbatim); the fix aligns the *preview* to it.
2. **Claims verified against code:** all line refs (payer gate, self-exclusion, both payer-inserts, persist) + rules `:470/:550/:556` re-grepped on branch HEAD.
3. **Read-path per write-path:** write = `customSplitParticipants` (+ `splitDistribution`); readers = `BalanceCalculator` (splits over `customSplitParticipants`) and the preview. After the fix both read the identical set → preview == ledger.
4. **Fields from the type:** `ExpenseEditorPayload{amount, description, scope, categoryId, payerParticipantId, customSplitParticipants, splitMode, splitDistribution}` — fix touches `payerParticipantId` (any member) + `customSplitParticipants` (may include self) + the preview display. No field added; **no `BalanceCalculator` change.**
5. **Data contract:** custom scope seeds `{currentUid}` (deselectable); payer dropdown lists all participants; custom picker lists all incl. self; preview renders `customSplitParticipants` verbatim (no payer insert).
6. **Arithmetic decomposition:** after removing the payer-insert, preview per-head = `amount / customSplitParticipants.length`. The "I paid, split me+him" money bug closes: with pre-select, custom = `{me, him}` → 2-way → him owes `amount/2` (was: custom `{him}` → him owes full while preview showed 2-way).
7. **Adversarial pass (orthogonal axis = identity / payer-not-in-split):** log that **Codex** paid, split among **{Gemini}** only (payer ∉ custom set). Persist `customSplit={Gemini}`, `payer=Codex`. `calculateBalances`: Gemini owes full, Codex paid full → Codex `+full`, Gemini `−full`, conserved. Preview (after fix) shows **{Gemini} owes full** — matches the ledger. (Old code inserted Codex into the preview → showed a 2-way split that the ledger never recorded — the exact lie #247 kills.) Must add a test for this. Also: `{him}`-only set (length 1) → the `< 2` gate (`:478`) keeps the exact/shares/percent split-mode sheet disabled (can't build a non-equal distribution over one person) — test it so a future re-add of the payer-insert (re-opening the divergence) is caught.

## 5. Tests
**Widget — `split_scope_selector_test.dart` — REWRITE the two stale tests (Gate R1 P1; CLAUDE.md: delete obsolete assertions, don't patch):**
- `:14-36` "hides payer for non-leaders" (`expect(find.byKey(LedgerKeys.payerSectionLabel), findsNothing)` at `:29`) → **invert** to "shows payer for non-leaders" (`findsOneWidget`), any participant selectable.
- `:38-62` "custom scope filters the current user" (`expect(find.text('Layla Hassan'), findsNothing)` at `:55`) → **invert** to "custom picker includes the current user" (`findsOneWidget`); toggling self updates the set.
- `:64-86` "leader payer selector defaults to the current user" → **stays as-is** (Gate R2 P2): still valid (leader-default seeding + change emission). It uses `currentUid='uid-yasmin'` = the leader, so it does NOT prove non-leader visibility — that proof now lives in the rewritten `:14-36`. Keep both; don't mistake this one for ungate coverage.
- NEW: entering custom scope pre-selects the participant-resolved current user (seeded once, `_custom.isEmpty` guard).
**Widget — `expense_editor_body_test.dart`:**
- **preview == persisted (the money fix):** set custom `{him}` with payer = me; preview shows exactly `{him}` (1 way · full amount), submitted `customSplitParticipants == {him}` — preview count == persisted count (no payer auto-insert).
- **empty-custom == global (Gate R1 P1):** custom set emptied → preview shows ALL participants (mirrors the calculator's global fallback), not "no split".
- payer-∉-set + `< 2` gate: custom `{him}` (length 1) → split-mode sheet stays disabled.
- S2 (non-leader logs other-payer) and S3 (creator in an exact custom split) attribution flows produce the expected payload.
- `balance_calculations_test.dart` stays green (no calculator change) — the ONLY suite that stays green untouched; the selector tests are rewritten per above.

## 6. Out of scope (named)
- Edit/delete rights for on-behalf-of expenses (creator + payer + leader) — a rules/B1 change, tracked separately.
- Per-person preview amounts for non-equal modes (#242) — overlaps `_SplitPreviewCard`; coordinate if both land.
- "(me)" badge in the custom picker tile (Gate R2 P3) — payer-only today; a deselectable pre-checked row is sufficient.
- Renaming `editorNoOtherParticipants` → a generic "no participants" string (Gate R2 P3) — branch is degenerate-unreachable post-fix; ARB EN/AR churn not worth it now.
- #249 (deferred), #244/#250 (in PR #253).
