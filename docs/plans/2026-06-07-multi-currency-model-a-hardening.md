# Multi-currency #261 — Model A hardening (foundation, no UI)

**Date:** 2026-06-07
**Issue:** #261 (post-1.0 follow-up to #61). Refs #70, #242.
**Scope decision (user, this session):** **Model A (one-currency-per-group)** as the 1.x model. **Ship the foundation + enforcement only — no currency picker, no UI change.** Every group stays OMR. Currency is **immutable after creation**.
**Model B (per-currency buckets):** explicitly DEFERRED to a separate post-1.x epic (needs a per-currency-breakdown UI decision + mixed-currency parity coverage written RED-first). Per-event currency is **rejected** (Event has no currency field; the group rollup stays blind one level up).

This plan was produced from a 7-reader Understand workflow + a steelman-A/steelman-B/adversary Design judge-panel, both run against live code on `main @ 9ea5ef8`. It is a **Gate-category** change (money math + `firestore.rules` + a schema field with read+write paths) → `/run-the-gate` before implementation; each PR also goes through `/automerge` (fresh review + refuter) at merge.

---

## Why (verified current state)

Per-expense money is fully currency-correct across 10 ISO codes (`OMR USD EUR GBP SAR AED JPY KWD BHD QAR`); serialize/quantize/allocate/display all key off a per-record `currency` field. The **cross-expense/event/group aggregation is currency-blind** on both client and server — it sums bare `Decimal`s with no currency key. This is latent-not-live ONLY because every write path hardcodes `'OMR'` (#61).

Model A makes the existing scalar `Map<uid, Decimal>` net **correct-by-construction**: one currency per group ⇒ every sum is dimensionally homogeneous ⇒ the scalar gate is a true settled-check. It touches **zero** allocator/aggregation arithmetic, so the byte-for-byte client/server parity contract (`delete_group_balance_parity_test.dart`) is preserved with no new cases required, and migration is a **no-op** (all existing data is OMR == the default).

### Two latent money bugs found (fix regardless of model)

1. **Currency clobber** — `expense_service.dart:196-199` does `final cur = currency ?? 'OMR'` on any amount edit, and `edit_expense_screen.dart:_save` (lines 104-131) never passes `currency:`. The instant a non-OMR expense exists, editing its amount **rewrites `currency='OMR'` and re-encodes `amountFils` at OMR's 1000-scale** → a USD 10.00 (1000 fils) silently becomes OMR 1.000. Same clobber in `_encodeDistribution(..., currency ?? 'OMR')` at `:213-217`.
2. **False-zero delete gate** — `deleteGroup.ts:254-255` filters a flat scalar `net` for `!value.isZero()`. `+10 OMR / −10 USD` nets to `Decimal 0` → passes → irreversibly deletes a group with real per-currency debt. `leaveGroup.ts:86-88` and `removeMember.ts:123-125` gate single actors on the same blind scalar.

---

## Verification principles applied (CLAUDE.md Operating Contract)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).** The `currency` on an `Expense` is **BOTH**: displayed AND feeds `MoneySerializer.toSubunits` (a write) + the balance fold. The clobber is exactly an OUTBOUND path that was being silently rewritten. PR-0a treats it as OUTBOUND (must preserve/validate, never default).
2. **Concrete claims verified against code (not docs).** Every line ref below was read on `main @ 9ea5ef8` this session: clobber `expense_service.dart:196-199,213-217`; callsite `edit_expense_screen.dart:104-131`; gate `deleteGroup.ts:254-255`, `leaveGroup.ts:86-93`, `removeMember.ts:123-130`; oracle folds `groupNetBalance.ts:432,475,499`; rules `validExpenseBase:565`, `validEventSettlementBase:688/702`, `validGroupSettlementBase:880`, `validCreatorMetadataUpdate:296-305`; client mutation `group_provider.dart:271-283`; rules-test pivot `firestore-rules-publish-readiness.test.ts:1706`.
3. **One read-path per write-path.** After PR-0a, who reads `expense.currency` post-edit? → `RAmount`/`expense_card` display + `BalanceCalculator`/`recomputeNet` folds. Both now read the preserved (not clobbered) currency. After PR-1, who reads `group.currency`? → the new rules equality on every expense/settlement write (and existing display).
4. **Fields enumerated from the type.** `validExpenseBase` key allowlist (`firestore.rules:538-558`) and `validEventSettlementBase` (`:681-695`) read directly; `currency` is already an allowed key in both → **no `hasOnly` change**, only an added relational predicate.
5. **Data contracts spelled out.** `recomputeNet` return shape changes from `{ net, liveEventRefs }` to `{ net, liveEventRefs, currencies: Set<string> }` (exact). Gate predicate: `currencies.size > 1`.
6. **Arithmetic decomposition.** N/A for the math (no allocator change). The decomposition that matters: the gate's `currencies` set must be built **only from docs that actually contribute to `net`** (inside the universe-gated folds), so a settled-and-deletable single-currency group is never falsely flagged.
7. **Adversarial pass on an orthogonal axis.** The fix axis is *currency*. Worked examples must exercise the *settlement* and *identity* axes: (a) a group settled to fake-zero across two currencies (PR-0b), (b) a creator mutating `group.currency` after an expense exists (PR-1), (c) the `_encodeDistribution` exact-split currency path, not just the scalar `amountFils` (PR-0a).

---

## PR-0a — Preserve expense currency on amount edit (clobber fix)

**Gate-category** (money math), tiny diff. Client + service. **No deploy** (client-only).

### Changes
- `lib/features/ledger/services/expense_service.dart` `updateExpense`:
  - When `amount != null`, **require** `currency`: if `currency == null` throw `ArgumentError('updateExpense requires currency when amount is set')` instead of `?? 'OMR'` (`:196-199`). **Scope the throw to the `amount != null` path ONLY.** Do **NOT** change the `_encodeDistribution(..., currency ?? 'OMR')` path at `:213-217` to throw — a split-mode-only edit legitimately passes neither `amount` nor `currency` (`expense_service_test.dart:244`), and `shares`/`percent`/`equally` encodings are scale-independent; the only scale-sensitive mode (`exact`) is covered because `_save` now always threads `currency`, so it's never null on a real edit. Keep `_encodeDistribution`'s OMR default.
- `lib/features/ledger/screens/edit_expense_screen.dart` `_save`: pass `currency: original.currency` to `updateExpense` (currently omitted) — **unconditionally**, so both the `amountFils` re-encode and `_encodeDistribution` get the real currency.
- **Existing callers that must be updated** (verified — the spec's earlier "only edit_expense_screen" was wrong):
  - `test/unit/expense_service_test.dart:213` and `:288` call `updateExpense(amount:)` with no `currency:` → add `currency: 'OMR'` and re-verify `amountFils` scaling. `:244` (split-mode-only, no amount) is a **regression-pin** — must keep passing unchanged.
  - `test/features/ledger/edit_expense_screen_test.dart:108`, `:143`, `:204` mocktail stubs `when(()=>service.updateExpense(...))` omit a `currency:` matcher → after `_save` passes `currency: original.currency`, the stub no longer matches. Add `currency: any(named: 'currency')` (or concrete `'OMR'`) to each stub.

### RED-first test (money, table-driven) — `test/unit/` or `test/features/ledger/`
Edit an expense amount across currencies; assert currency **preserved** and `amountFils` re-encoded at the **right scale**:
| start | edit amount | expect currency | expect amountFils |
|---|---|---|---|
| USD 10.00 | 12.00 | USD | 1200 (÷100) |
| OMR 10.000 | 12.000 | OMR | 12000 (÷1000) |
| JPY 1000 | 1200 | JPY | 1200 (÷1) |
+ a currency-less amount edit **throws** (not defaults OMR). Each row must **FAIL on current code** (currency → 'OMR', `amountFils` mis-scaled) before the fix → then GREEN.

### Acceptance
- [ ] RED proven (pasted failing-before output), then GREEN.
- [ ] `flutter analyze` clean; ledger suite green.
- [ ] No behavior change for an OMR expense edit (regression-safe).
- [ ] `expense_service_test.dart:213/:244/:288` and `edit_expense_screen_test.dart:108/:143/:204` updated and green (the 5 callsites the throw/threading touches).

---

## PR-0b — Reject delete/leave/remove on mixed-currency groups (false-zero guard)

**Gate-category** (Functions gate), server-only. **Deploy** after merge (deploy-ceremony). Defends the legacy/Admin-doc edge that Model A's scalar gate cannot (under Model A + immutable currency this is unreachable for app-created data — pure defense-in-depth, and it permanently closes the false-zero money-loss path).

### Changes
- `functions/src/callables/groupNetBalance.ts`:
  - `RecomputeResult` gains `currencies: Set<string>`.
  - **Declare `const currencies = new Set<string>();` at FUNCTION scope** — next to `net` at `:347`, BEFORE the `for (const eventDoc of liveEventDocs)` loop (`:361`). A per-event declaration would only detect mixing *within* one event and miss the OMR-expense-in-e1 + USD-expense-in-e2 cross-event case.
  - **Build the set from the EXPENSE fold ONLY** — `currencies.add(currency)` at `:432` (event expenses), using the `currencyOf(...)`-normalized code. **Do NOT fold settlement currencies** (`:475` event settlements, `:499` group settlements). *Why (Gate P1):* settlements are written **OMR-scale even in non-OMR groups** by established convention (`settle_up_screen.dart:169/243`, `settlement_service.dart:75` hardcode `'OMR'`), so a legitimate single-expense-currency group routinely has `{expenseCurrency, OMR}`. The per-**expense** currency is the only dimension that actually varies under Model A, and a cross-currency false-zero can only arise from mixed-currency **expenses** — so the expense fold is both necessary and sufficient. Folding settlements would brick `deleteGroup` test 9 (USD expense + OMR settlement) and any real settled non-OMR group.
  - Return `{ net, liveEventRefs, currencies }`.
- `deleteGroup.ts` (`:254`), `leaveGroup.ts` (`:86`), `removeMember.ts` (`:123`): destructure `currencies`; **before** the `isZero()` check, `if (currencies.size > 1) throw new HttpsError('failed-precondition', '<scope> not supported for a mixed-currency group.')`.

**Residual boundary (Model B, NOT closed here — by design):** this guard closes the mixed-**EXPENSE**-currency false-zero. It does NOT close a single-expense-currency group "settled" by a settlement in a *different* currency (e.g. a USD debt offset by an OMR settlement that fakes a Decimal-0 net) — settlements are excluded from the set on purpose (folding them breaks `deleteGroup` test 9 + the client-parity contract + creates stuck groups). That expense-vs-settlement-scale mismatch is the deeper currency-blindness Model B owns; it is **unreachable for app data under Model A** (every write is OMR; after Phase 2 the picker also moves settle-up off the OMR hardcode so a non-OMR group's settlements are non-OMR too) and pre-exists this guard. Documented in `groupNetBalance.ts` `RecomputeResult`.

### RED-first test (money/safety, table-driven) — `functions/test/callables/{deleteGroup,leaveGroup,removeMember}.test.ts`
- **Explicit fixture (no settlements):** group with exactly two participants A, B and TWO global-equal expenses, one `currency:'OMR'` and one `currency:'USD'`, with `amountFils` chosen so each uid's numeric paid == owed → `net = {A:0, B:0}` (fake zero) yet `currencies = {OMR, USD}`. E.g. A pays expense-1 `amountFils:10000` OMR (= 10.000, global-equal A+B → each owes 5.000), B pays expense-2 `amountFils:1000` USD (= 10.00, each owes 5.00): A net `= 10 − 5(OMR) − 5(USD) = 0`, B net `= 10 − 5 − 5 = 0` numerically. → `deleteGroup` / `leaveGroup(A)` / `removeMember(B)` each **REJECT** `failed-precondition` (mixed-currency). Must **FAIL today** (flat `isZero()` passes and would delete docs).
- **Cross-event mixing case (locks function-scope declaration):** an OMR expense in event `e1` and a USD expense in event `e2` (each settled within its event, or arranged to net zero) → `deleteGroup` **REJECTS** (mixed-currency). A per-event `currencies` set would wrongly PASS this; the function-scope declaration catches it.
- **Regression-pin — `deleteGroup.test.ts:486` ("non-OMR group", USD expense + OMR settlement) still PASSES:** with the expense-fold-only set, `currencies = {USD}`, size 1 → not flagged. (Correct the earlier mischaracterization: test 9 is *not* single-currency end-to-end — it deliberately mixes a USD expense with an OMR settlement; it passes precisely because the guard ignores settlement currency.)
- An unsettled single-currency group still rejects via the existing `isZero()` path (unchanged).

### Acceptance
- [ ] RED proven, then GREEN; existing deleteGroup/leave/remove suites green (esp. `deleteGroup.test.ts:486`).
- [ ] `currencies` built from the **expense fold only** (`:432`); settlement folds (`:475`/`:499`) NOT included.
- [ ] `npm run build` / `tsc` clean; deploy via `deploy-ceremony`; advance `backend-deployed` tag; record in `DEPLOY-LEDGER.md`.

---

## PR-1 — Rules: enforce `currency == group.currency` + lock currency immutable

**Gate-category** (`firestore.rules` + schema). Rules + client. **Deploy** rules after merge. This makes `group.currency` **authoritative** and **enforced** before any future client (Phase 2) can write a 2nd currency — the "rules-before-client" ordering. Today every write is OMR and `group.currency` is OMR, so the equality is a **safe tautology**; it becomes live enforcement when Phase 2 moves the write hardcodes.

### Changes
- `security/firestore.rules`:
  - Add a helper `currencyMatchesGroup(d) { return d.currency == groupData(groupId).currency; }` in the `/{module}/{docId}` scope (next to `splitValuesNonNegative`).
  - **Expenses — diff-gated, NOT in `validExpenseBase`** (critical: `validExpenseBase` re-runs wholesale on every update INCLUDING soft-delete; putting the equality there would block soft-deleting a legacy currency-mismatched doc — same soft-delete trap the file already avoids for `splitValuesNonNegative`, see `:495-503`). Mirror that precedent exactly:
    - `validExpenseCreate` (`:580`): add `&& currencyMatchesGroup(request.resource.data)` (unconditional, alongside `splitValuesNonNegative` at `:585`).
    - `validExpenseUpdate` (`:627`): add `&& (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['currency']) || currencyMatchesGroup(request.resource.data))` (diff-gated, mirroring the `splitValuesNonNegative` update gate at `:658-659`) — so a pure soft-delete (which doesn't touch `currency`) is never re-checked, but any update that *sets* currency must match the group.
  - **Event-settlements — inline is safe** (create-only: `validEventSettlementBase` is reached ONLY via `validEventSettlementCreate`; settlement updates are denied at `allow update: if validExpenseUpdate()` which is module-gated to `'expenses'`, and the `match /settlements/{settlementId}` block is `allow update/delete: if false`). Add `&& currencyMatchesGroup(data)` in `validEventSettlementBase` (after `:702` `validSettlementCore(data)`); update the `:875-879` deferral comment to: resolved under #261; Phase 2 MUST move `settle_up_screen`/`add_expense` off the `'OMR'` hardcode to `group.currency` or non-OMR groups' settle-up/expense writes will be denied (intended fail-loud ordering).
  - `validCreatorMetadataUpdate` (`:296-305`): drop `'currency'` from the `hasOnly(['name','currency','updatedAt'])` at `:299` → `hasOnly(['name','updatedAt'])`; remove the now-dead currency branch at `:302-303`. (Currency stays settable ONLY at `validGroupCreate:289`.)
  - **Billed-read note (Gate-cleared):** the expense write path ALREADY fetches the group doc — `validExpenseCreate`/`validExpenseUpdate` → `eventAllowsClientWrites` → `groupAllowsClientWrites` → `groupData(groupId)` (`firestore.rules:106-112,134-139`). Firestore dedupes identical `get()` within one rule evaluation, so `currencyMatchesGroup` adds **zero** new distinct document reads and cannot affect the per-request access budget. (No cost concern; note it in the rule comment.)
- `lib/features/groups/providers/group_provider.dart` `updateGroup` (`:271-283`): remove the `currency` param and the `updateMap['currency'] = currency` line so the client cannot attempt a currency change (defense-in-depth alongside the rule). Only lib caller is `group_info_section.dart:64` (`name:` only) — unaffected.

### RED-first tests (rules, table-driven) — `functions/test/firestore-rules-publish-readiness.test.ts`
- **FLIP** existing test at `:1706`. Exact current title: `'#193 event settlement with a divergent supported currency is allowed (cross-currency equality deferred to #61)'` → rename to `'#261 event settlement with a divergent supported currency is denied (cross-currency equality enforced)'` and change `assertSucceeds`→`assertFails` at `:1710`. (Cleanest RED→GREEN: currently asserts ALLOW.)
- **MODIFY existing test at `:731-748`** (`'member cannot take ownership, but creator can update metadata'`): its success update at `:742-746` does `update({name:'Updated Crew', currency:'USD', updatedAt})` → **drop `currency:'USD'`** from that update (keep `name`+`updatedAt` → `assertSucceeds` as the regression-pin). This is a **MODIFY, not an add** — PR-1 drops `currency` from the metadata allowlist, so this existing success assertion breaks otherwise.
- **ADD** creator currency-change DENY: group `currency:'OMR'`; a creator `update` touching `currency` (→ 'USD', plus `updatedAt`) → **assertFails** (must FAIL today — currently allowed via the hasOnly + validCurrency branch).
- **ADD** expense divergent-currency: group OMR; an expense **create** with `currency:'USD'` → **assertFails**; create with `currency:'OMR'` → **assertSucceeds**; an **update** that *changes* `currency` to `'USD'` → **assertFails**. **The update payload MUST carry `lastEditedBy: '<caller-uid>'`** (the caller) — `validExpenseUpdate` now unconditionally requires `lastEditedBy == auth.uid` (#248 PR4), so without it the denial isolates the wrong rule and the test passes vacuously without exercising `currencyMatchesGroup`.
- **ADD soft-delete carve-out (the trap) — Gate-R2 corrected to a DIVERGENT fixture:** Admin-seed (`seedExpense`/`withSecurityRulesDisabled`) a **`currency:'USD'` expense in OMR group `g1`** (`createdBy:'member'`), then a **member** soft-deletes it (`isDeleted:true`, `deletedAt`, `lastEditedBy:'member'`; **no `currency` in the diff**) → **assertSucceeds**. *Why divergent, not OMR-in-OMR:* an OMR-in-OMR soft-delete passes under BOTH the diff-gated placement AND a (wrong) unconditional `currencyMatchesGroup` in `validExpenseBase` (`'OMR'=='OMR'`), so it is non-discriminating and the "proves the diff-gate" rationale is false. The USD-in-OMR doc **FAILS** under unconditional placement (`'USD'!='OMR'` → deny) and **PASSES** with the diff-gate (currency absent from the soft-delete diff). Mirrors the live #192 negative-split carve-out at `:1653-1661`.
- Regression-pin: group-settlement divergent currency stays DENIED (`:1698`); event-settlement matching currency ALLOWED.
- **Stale-deferral comment sweep (Gate-R3):** flipping the event-settlement equality contradicts THREE in-tree "#61-deferred" notes — update all three to attribute to #261 + the Phase-2 hardcode-move dependency: (1) the rule prose at `firestore.rules:875-879`; (2) the **test-block header comment** at `firestore-rules-publish-readiness.test.ts:1663-1669` ("Event-settlement cross-currency equality is DEFERRED to #61 … tautology-today / landmine-tomorrow"); (3) the **flipped test's own inline comment** at `:1707-1708`. Leaving a comment asserting the opposite of the deployed rule is exactly the doc/code drift the merge-time spec-conformance reviewer flags.
- **`lib/`-side — DELETE, not edit:** remove the two whole tests at `test/unit/group_service_test.dart:342-370` (`'updateGroup with currency updates currency field'`) and `:374-407` (`'updateGroup with both name and currency updates both fields'`) — they exercise the removed `updateGroup(currency:)` param and are compile-breakers. Also rename/remove the stale-title test at `:113` (`'updateGroup function signature accepts name and currency'`, cosmetic — body is `expect(GroupService.new, isNotNull)`, compiles regardless).
- **`lib/`-side — `test/features/groups/group_settings_screen_test.dart` (Gate-R2 P1, the repo's ONLY `extends GroupService` override):** removing `currency` from the base `updateGroup` makes the `@override` at `:404-410` an `invalid_override` compile error that fails the whole file. Mirror the param removal: drop `String? currency` from (1) the `_UpdatingGroupService.updateGroup` `@override` (`:407`) and its forwarding `onUpdateGroup(...)` call (`:409`); (2) the `onUpdateGroup` typedef on the service field (`:399-401`) and the `_wrapGroupInfoSection` parameter typedef (`:304-306`); (3) the call-record type (`:568`), every `onUpdateGroup` callback signature/body (`:571-572/:592/:614/:650/:669`), and the `currency: null` assertion (`:584` → assert `(groupId:, name:)` only). Then `flutter analyze` the file (no residual `invalid_override`) and run it green.

### Acceptance
- [ ] All rules tests RED→GREEN; full `functions` rules suite green; `firebase deploy --only firestore:rules` dry-validate clean.
- [ ] `flutter analyze` clean after the `updateGroup` signature change; group tests green.
- [ ] Deploy rules via `deploy-ceremony`; record in `DEPLOY-LEDGER.md`.
- [ ] Comment updated to attribute to #261 and spell out the Phase-2 hardcode-move dependency.

---

## Deferred (NOT this session)

- **Phase 2 (user-visible):** revive the create-group currency picker (recoverable from the #61 removal commit) wired to `createGroup(currency:)`; thread `group.currency` into `add_expense_screen._tripCurrency` (`:33`), `expense_editor_body._tripCurrency` (`:141`), `settle_up_screen` (`:169/:243`). Must land WITH the rules already deployed (PR-1). At that point a NEW group can be all-AED/all-USD end-to-end. Add a currency-table keyset-equality test (5 tables must match).
- **#70 display-relabel:** standalone cosmetic; no model dependency.
- **Model B (per-currency buckets):** separate post-1.x epic; requires mixed-currency parity cases written RED-first + a per-currency-breakdown UI (no FX source exists).

## Risks to watch (for the Gate + refuter)
- **Currency-mutation has TWO paths**: the rule (`validCreatorMetadataUpdate:299`) AND the client (`group_provider.dart:280`). A spec that locks only one leaves the other open → the refuter's #1 hunt target. (Server rule is the true gate; client removal is defense-in-depth.)
- **`currencies` set scope** (PR-0b): must be built from contributing folds only, or a settled single-currency group could be falsely flagged mixed and become undeletable.
- **Event-settlement equality + OMR-hardcoded settle-up**: safe only because no non-OMR group can exist this session (create=OMR + immutable). The Gate must confirm there is no path to a non-OMR group in this PR set.
- **`_splitTolerance` = 0.001** (`expense_provider.dart:253`) is OMR-shaped; harmless under Model A (homogeneous). Flag for the deferred Model B epic (per-currency tolerance), not here.
