# Spec: Firestore rules value-domain hardening (#192 / #193 / #194)

**Date:** 2026-06-02
**Surface:** `security/firestore.rules` (server-side, deploys without a Play release) + small client tails (ride next app release).
**Gate:** MANDATORY — touches `firestore.rules` + money. Run a fresh-context reviewer (Opus 4.8, zero session history) against this doc before writing code. Iterate to zero P1s.
**Batch scope:** the three *rules-expressible value-domain* gaps. Functions rate-limiting (#197/#198) is a separate batch (different surface).

---

## 0. Why these three together

All three are the same class: **rules enforce field *shape* (`is map`, `is string`, `size()==3`) but not the field's *value domain*** (sign, range, charset, length, currency allow-list). They're one file, one deploy command (`firebase deploy --only firestore:rules`), one test harness (`test_rules/`, `@firebase/rules-unit-testing` + emulator). Each has a small client tail that is defense-in-depth / UX and rides the next app release — but the *security fix is the rules change*, which deploys server-side immediately (deploy-first, the project's established pattern).

Deploy-first is safe here because **every one of these is unreachable from the shipping UI** (the UI already strips/clamps/pins). We are hardening the trust boundary against a *crafted authenticated write*, not fixing a user-facing bug. So the rules can tighten ahead of the client with zero user impact.

---

## 1. Verified current state (code, not memory — re-grepped 2026-06-02)

### Shared predicates (`security/firestore.rules`)
- `nullableString(value)` (:14-16): `value == null || value is string` — **type only**, no length, no charset.
- `isValidDisplayName(s)` (:24-31): `is string && 1≤size≤32 && trim≥1 && matches('^[^\x00-\x1f\x7f]+$') && not "(former member)"`. **This is the template for #194.**
- `validCurrency(value)` (:48-50): `value is string && value.size() == 3` — **type + length only**. Used by: `validSettlementCore` (:65), expense create/update (:244 group create, :258 metadata update, :488 expense base).
- `validSettlementCore(data)` (:60-70): includes `validCurrency(data.currency)` and `nullableString(data.note)`.
- `groupData(groupId)` (:76-78): `get(groupPath(groupId)).data` — group doc fetch; group always has `currency` (group create requires `validCurrency`, :244).
- `validExpenseSplit(data, enforceParticipantKeys)` (:452-458): checks `splitMode in [...]` and `splitDistribution is map && keys().hasOnly(participants())`. **No value check.**

### Supported currencies (`lib/core/services/money_serializer.dart:8-19`)
`_currencyScale` keys (10): **OMR, USD, EUR, GBP, SAR, AED, JPY, KWD, BHD, QAR**. `isSupported()` is case-insensitive (`.toUpperCase()`). `fromSubunits`/`_scale` **throw `ArgumentError`** on an unknown code.

### Write paths — `splitDistribution` (#192)
- `expense_service.dart:124-130`: key written **only inside `if (splitMode != null && splitMode != SplitMode.equally)`**. On equal/global split the key is **ABSENT** (not `{}`, not `[]`).
- `_encodeDistribution` (:328-345): exact→subunits, percent→`(value × 1000).toInt()`, shares→raw int. All **non-negative ints in valid cases**.
- Empty map `{}` only producible via `_encodeDistribution(const {})` — reachable **only** when service called with non-equal mode + null distribution. UI never does this: `expense_editor_body.dart:219` sends `_splitMode==equally ? null : _splitDistribution`, and a non-equal `_splitMode` is only set via `showCustomSplitSheet` which returns one entry per participant (≥2 enforced, :341). **Empty map ⇒ crafted write only; harmless (no negative).**
- NOTE: the "split 0 ways" bug (memory) is `customSplitParticipants`/`participantCount`, **not** `splitDistribution`. Different field. Confirmed.

### Write paths — settlement currency (#193)
- Group settlements: `group_settle_up_screen.dart:264,353` pass `currency: group.currency` ⇒ `settlement.currency == group.currency` **holds by construction**.
- Event settlements: `settle_up_screen.dart:223` **hardcodes `const currency = 'OMR'`** (also `:149`). Events have **no** currency field (`events/models/` has none). So event-settlement currency == group currency **only because both are OMR today** (#61: group create + editor pin OMR).
- Read path (the crash leg): `settlement_model.dart:95` `final currency = data['currency'] as String? ?? 'OMR'` → `:111` `MoneySerializer.fromSubunits(amountFils, currency)` → **throws on unsupported code**. No `isSupported` fence (contrast expense path `expense_provider.dart:155-157`, the #47 fence).

### Write paths — free text (#194)
- `validSettlementCore` `note` (:66) and expense `subGroupId`/`receiptUrl`/`categoryId`/`description`/`note` (:490-497) all use bare `nullableString` (type only).
- `description` → `activity_logs.logText` (`expense_service.dart:210-211`); settlement `note` rendered verbatim (`settlement_service.dart:86`). Same rendering surfaces that motivated strict names.
- `receiptUrl` is a **dead** field (media stripped Phase 39, no Storage SDK) — nothing writes it. `categoryId`/`subGroupId` are app-generated short ids.

---

## 2. The fixes

### #192 — non-negative `splitDistribution` (rules-only) + client guard (next release)

**Spike result (emulator, 2026-06-02):** `List<int>.values().join(',')` **coerces ints to a string** in the rules engine. Verified: `{a:15000,b:10000}`→ALLOW, `{a:0,b:25000}`→ALLOW, `{a:15000,b:-5000}`→DENY, `{}`→DENY. So non-negative-int validation **is** loop-free expressible.

**LOCKED DESIGN (Gate round-2 P1: must NOT go inside `validExpenseSplit`).** `validExpenseSplit` is called by `validExpenseBase` (:493), which `validExpenseUpdate` runs **wholesale on every update including soft-delete** (:558, full `request.resource.data` = the merged post-write doc, including the *unchanged* legacy `splitDistribution`). #192's threat model is that forged-negative `splitDistribution` docs can *already* be in prod (today's rules only check `is map`). Putting the value-regex inside `validExpenseSplit` (gated only on presence) would re-validate that legacy value on soft-delete → `PERMISSION_DENIED` → **undeletable record → soft-delete-invariant breakage** — the exact regression class caught for #194. (The existing `keys().hasOnly(participants())` check is safe on soft-delete only because it sits behind `!enforceParticipantKeys`, which is false on soft-delete; the new value-check must be guarded too.)

So: **leave `validExpenseSplit` UNCHANGED.** Add a new predicate, enforced unconditional on CREATE, diff-gated on UPDATE (mirrors #194):
```
function splitValuesNonNegative(d) {
  return !d.keys().hasAny(['splitDistribution'])
    || d.splitDistribution.values().size() == 0
    || d.splitDistribution.values().join(',').matches('^[0-9,]+$');
}

// validExpenseCreate wrapper — add (unconditional; no diff exists on create):
&& splitValuesNonNegative(request.resource.data)

// validExpenseUpdate wrapper — add (diff-gated; affectedKeys() = request.resource.data.diff(resource.data).affectedKeys()):
&& (!affectedKeys().hasAny(['splitDistribution']) || splitValuesNonNegative(request.resource.data))
```
- The `^[0-9,]+$` regex rejects any value whose string form contains `-`, `.`, or `e` ⇒ enforces **non-negative integer** per entry across all three modes (the `-50000` for a `-50%` entry is denied).
- `values().size() == 0 ||` preserves the current "empty map allowed" behavior (zero regression for the crafted-but-harmless empty case).
- Diff-gating ⇒ a legacy/forged negative-`splitDistribution` doc is **still soft-deletable** (the field isn't in the soft-delete diff, so the check doesn't fire). New creates and edits-that-touch-`splitDistribution` are blocked. This is the only correct placement.

**Client tail (next release):** per-entry `value >= 0` guard in `_allocateShares`/`_allocatePercent` → equal-split fallback (mirror the existing invalid-total fallbacks). UX/defense; not the security fix.

**HONEST RESIDUAL (must not over-claim):** rules have no numeric fold, so **sum == amount is NOT enforced**. A pure over-allocation with all-positive values (e.g. single `{p1:150000}` = 150%, no negative) is **still accepted by rules**. This matches #192's own "Suggested fix" (non-negative enforcement only); the sum/tolerance invariant stays in the client allocator. Document in the rule comment; do not claim "over-100 closed".

### #193 — settlement currency allow-list + read-fence (+ cross-currency equality, see Open Q)

**(a) Allow-list — `validCurrency` (:48-50):**
```
function validCurrency(value) {
  return value is string
    && value in ['OMR','USD','EUR','GBP','SAR','AED','JPY','KWD','BHD','QAR'];
}
```
- **Blast radius:** `validCurrency` is shared — tightening also constrains **expense** create/update (:488) and **group create/metadata** (:244/:258) to the allow-list. This is *beneficial and consistent* (rejects `'XYZ'` everywhere) and safe (app only ever writes supported codes). Surfaced explicitly; not a hidden side effect.
- Drops the `size()==3` check (allow-list entries are all 3 chars; redundant). All entries UPPERCASE to match `MoneySerializer` storage (the app never writes lowercase).

> Note (Gate P3): `settlement_model.dart:130 toFirestore()` also hardcodes `const currency = 'OMR'`, but it is **dead** — the write paths build their own maps in `settlement_service.dart` / `group_settlement_service.dart`; `toFirestore` is unused on the write path. Don't "fix" it as if it were live; it has no bearing on this batch.

**(b) Read-fence — client tail (next release), `settlement_model.dart:95`:**
```
final rawCurrency = data['currency'] as String? ?? 'OMR';
final currency = MoneySerializer.isSupported(rawCurrency) ? rawCurrency : 'OMR';
```
Mirrors the #47 expense fence so a legacy/forged unsupported-currency settlement degrades to OMR instead of throwing `ArgumentError` and erroring the **shared** settle-up stream for every member.

**(c) Cross-currency equality — SEE OPEN QUESTION Q1.** Proposed: add `&& data.currency == groupData(groupId).currency` to `validGroupSettlementBase` (safe — group settle-up passes group currency) and `validEventSettlementBase`. The event side is the landmine (Q1).

### #194 — bounded control-char-free free text (rules-only) + client mirror (next release)

**New predicate:**
```
function validFreeText(value) {
  return value == null
    || (value is string
        && value.size() <= 280
        && value.matches('^[^\\x00-\\x1f\\x7f]*$'));   // '*' not '+' — empty allowed
}
```

**LOCKED DESIGN (resolves the soft-delete regression the Gate flagged as P1).** Do NOT swap `nullableString → validFreeText` inside the shared base validators. `validExpenseBase` is re-run wholesale on every update including soft-delete (`validExpenseUpdate` rules:558 calls it with the full `request.resource.data`); `validSettlementCore` likewise via the settlement bases on `validEvent/GroupSettlementUpdate` (:610/:802). There is **no client length cap** on description/note (`expense_editor_body.dart` `_DescriptionField` and `record_payment_sheet.dart` note field have no `maxLength` — Gate-verified), so legacy prod docs with >280-char or control-char free text are reachable. Re-validating them on a soft-delete (which only diffs `isDeleted`/`deletedAt`) would `PERMISSION_DENIED` → **undeletable record → soft-delete-invariant breakage.**

Instead: **base validators keep `nullableString` (type check only, UNCHANGED). Enforce `validFreeText` in the wrappers — unconditional on CREATE, diff-gated on UPDATE.** Exact signatures:

```
// expense create wrapper (validExpenseCreate) — add:
&& validExpenseFreeText(request.resource.data)

function validExpenseFreeText(d) {           // all keys always written on create (expense_service.dart:120-133)
  return validFreeText(d.description)
    && validFreeText(d.note)
    && validFreeText(d.categoryId)
    && validFreeText(d.receiptUrl)
    && validFreeText(d.subGroupId);
}

// expense update wrapper (validExpenseUpdate) — add (mutable free-text fields per :543-557):
&& expenseFreeTextDiffOk()

function expenseFreeTextDiffOk() {
  return (!affectedKeys().hasAny(['description']) || validFreeText(request.resource.data.description))
    && (!affectedKeys().hasAny(['note'])        || validFreeText(request.resource.data.note))
    && (!affectedKeys().hasAny(['categoryId'])  || validFreeText(request.resource.data.categoryId))
    && (!affectedKeys().hasAny(['receiptUrl'])  || validFreeText(request.resource.data.receiptUrl))
    && (!affectedKeys().hasAny(['subGroupId'])  || validFreeText(request.resource.data.subGroupId));
}
// (affectedKeys() = request.resource.data.diff(resource.data).affectedKeys(); inline it to match the file's style.)

// settlement create wrappers (validEventSettlementCreate :592, validGroupSettlementCreate :786) — add:
&& validFreeText(request.resource.data.note)
// NOTE is unconditional on create (always in the create map). NO settlement update path exists:
// settlements are append-only (B3) — allow update: if false (:660 event, :820 group), services only .set().
// validEventSettlementUpdate/validGroupSettlementUpdate are DEAD (defined, never wired to an allow). Do NOT touch them.
```
Result: new expense writes + edits-to-free-text are bounded/charset-checked; **unchanged** legacy expense free text is never re-validated, so soft-delete of legacy expenses is never blocked. Settlement `note` is checked on its only write path (create). Type safety preserved everywhere by the untouched `nullableString` in the bases.

**Client tail (next release):** add a `validateFreeText`/`freeTextValidationError` helper in `name_validators.dart` (mirror the `displayNameValidationError` shape) for inline feedback instead of `permission-denied`. Add a `maxLength: 280` to the description/note inputs so the cap is reachable feedback, not a silent denial.

---

## 3. Open questions for the Gate

**Q1 — event-settlement cross-currency equality vs. #61 landmine.** Adding `data.currency == groupData(groupId).currency` to `validEventSettlementBase` is a **tautology today** (event settle-up hardcodes `'OMR'`, all groups OMR) AND becomes a **denial bug the instant #61 multi-currency ships** unless `settle_up_screen.dart:223/:149` is changed to use group currency. Options:
  - **(A)** Add equality to *both* bases now + add a `# DEPENDENCY(#61): settle_up_screen must write group currency or this denies` comment in rules + note on #61. Pro: real invariant, forces #61 correctness. Con: latent coupling.
  - **(B)** Add equality to `validGroupSettlementBase` only (safe by construction today); **defer** event equality to #61's PR (where the hardcode is fixed in the same change). Pro: no tautology, no landmine. Con: event settlements still accept divergent currency until #61.
  - **(C)** Defer all cross-currency equality to #61; this batch ships only allow-list + read-fence for #193.
  - **Recommendation: (B).** The allow-list already blocks the `'XYZ'` crash vector (the concrete harm today). Cross-currency *divergence* is only meaningful once multi-currency exists, which is #61's job — bundle the event-side equality with the fix that makes it non-tautological. Avoids shipping a landmine.

**Q2 — RESOLVED (Gate P1).** #194 migration safety: yes, this would have broken soft-delete of legacy long/control-char docs (no client length cap exists, Gate-verified). Resolved by the LOCKED DESIGN in §2 #194 — diff-gated `validFreeText` on update, base stays `nullableString`. Unchanged fields never re-validated ⇒ soft-delete of legacy docs never blocked.

**Q3 — RESOLVED (Gate P2/P3). Conclusion holds either way; don't overstate the mechanism.** Firebase docs say same-path access calls *may* be cached (and cached calls don't count) — not a guaranteed dedupe. But even counting **conservatively (no dedup)**: `validGroupSettlementCreate` only ever reads `groupPath(groupId)` (`isGroupMember` + `groupAllowsClientWrites` + the two `memberIds` reads + the new `currency` read) ≈ 5–6 same-path accesses — well under the 10-document-access limit. Event-settlement path = group + event docs, also well under 10. So adding the `.currency` comparison is safe regardless of caching. Q3 closed.

**Q4 — `receiptUrl`/`categoryId` under `validFreeText`.** 280-char cap on `receiptUrl`: dead field, fine. But if any code path *could* write a >280 URL, cap would block it. Confirm receiptUrl is truly never written (Phase 39). `categoryId` charset: app-generated ids are control-char-free, safe.

---

## 4. TDD test matrix (`functions/test/firestore-rules-publish-readiness.test.ts`, emulator)

**HARNESS CORRECTION (discovered during impl — code wins over the spec's earlier `test_rules/` note).** `test_rules/firestore.test.js` is **DEAD**: not referenced by any CI workflow, single commit `ad575c2`, never updated, and already 7/22 red against current main rules (drifted — invite codes now `get,list: if false`, group create/update tightened). The **live, CI-wired** rules harness is `functions/test/firestore-rules-publish-readiness.test.ts` (TS, `@firebase/rules-unit-testing`, run via `functions` `test:emulator` → `tool/run_firebase_emulator_tests.sh`, which `readiness_check.yml`/`release_android.yml` execute). It **already has** `validExpense`/`validSettlement`/`validGroupSettlement` builders, `seedExpense`/`seedEventSettlement`/`seedGroupSettlement`, `seedEvent`, `addGroupMember`, and the correct event-nested paths — so the Gate's "build `seedEvent` from scratch" P2 was against the wrong harness and is moot. New tests are ADDED there (no scaffolding needed). The #185 settlement-asymmetry tests are Dart (`test/...`), separate harness.

Write failing tests FIRST (RED), then tighten rules (GREEN). New cases:

**#192 splitDistribution (expense create):**
| case | dist | expect |
|---|---|---|
| equal split (key absent) | — | ALLOW |
| valid shares | `{a:2,b:3}` | ALLOW |
| valid exact subunits | `{a:15000,b:10000}` | ALLOW |
| zero entry | `{a:0,b:25000}` | ALLOW |
| negative entry | `{a:15000,b:-5000}` | DENY |
| empty map | `{}` | ALLOW (preserved) |
| **soft-delete of legacy expense w/ negative dist** (diff = isDeleted/deletedAt only) | unchanged `{a:-5000}` | **ALLOW (must not regress — orthogonal soft-delete axis)** |
| edit that re-sends a negative dist | `{a:-5000}` in diff | DENY |

**#193 currency (settlement create, event + group):**
| case | currency | expect |
|---|---|---|
| supported (OMR) | `OMR` | ALLOW |
| unsupported | `XYZ` | DENY |
| wrong length / lowercase | `om` / `omr` | DENY |
| (Q1-dependent) group settlement, currency≠group | divergent | DENY |

**#194 free text — expense create/update + settlement CREATE (no settlement update path exists):**
| case | field / path | value | expect |
|---|---|---|---|
| null | expense create `description` | null | ALLOW |
| normal | expense create `description` | `"Dinner"` | ALLOW |
| empty string | settlement create `note` | `""` | ALLOW |
| newline/control char | expense create `description`; settlement create `note` | `"a\nb"`, `"\x00"` | DENY |
| > 280 chars | expense create `description`; settlement create `note` | 281×`"a"` | DENY |
| edit description to control-char | expense update (`description` in diff) | `"a\nb"` | DENY |
| **soft-delete of legacy long-description expense** (diff = isDeleted/deletedAt only) | expense update | unchanged 500-char `description` | **ALLOW (must not regress)** |

Plus: keep all pre-existing `functions/test/firestore-rules-publish-readiness.test.ts` tests green — no regression. The Dart suite (`flutter test`) only matters for the client tails (separate PR); the rules-only PR's gate is the functions emulator suite.

---

## 5. Deploy & rollout

1. RED tests → tighten rules → emulator GREEN → existing suite GREEN.
2. **Gate** (fresh Opus 4.8) on this spec → zero P1s before code.
3. PR to `main` (branch-protected; readiness check). Rules-only diff + new rules tests. Client tails are a *separate* PR batched into the next app release (NOT this PR — one concern per PR).
4. Deploy `firebase deploy --only firestore:rules` to `rihla-safar` after merge. (Rules deploy is independent of the prod-state release ceremony — that gate is about Functions/AAB, per CLAUDE.md.)
5. Client tails (#192 allocator guard, #193 read-fence, #194 client validator) ride the next versioned client release; track as a follow-up.

## 6. Out of scope (explicit)
- #197/#198 Functions rate-limiting (different surface).
- Sum-equals-amount invariant for splits (no numeric fold in rules; client allocator owns it).
- #61 multi-currency editor/group-create un-hardcoding (this spec *constrains* it via Q1, doesn't do it).
- Over-100%-without-negative percent (not expressible; client total-tolerance owns it).
