# Plan — #48 (sub-part): extract shared settlement validator + emulator-rules tests

**Issue:** #48 (P1, "Group settlement names permanently stale after member rename")
**This plan covers only the self-contained rules-cleanup sub-part**, not the P1 core.

## Scope

**In:**
1. Extract a shared `validSettlementCore(data)` function in `security/firestore.rules`, called by both `validEventSettlementBase` and `validGroupSettlementBase`. **Behavior-preserving.**
2. Document the `eventId == groupId` sentinel inline in the rules (points to #71).
3. Add the missing/asymmetric settlement rules tests in `functions/test/firestore-rules-publish-readiness.test.ts` — they double as the refactor's characterization safety net.

**Out (explicitly):**
- The name-staleness P1 core (3 options in #48 body — stop denormalizing / rule-gated update / accept+document). Still product-decision-blocked.
- Changing the `eventId == groupId` sentinel itself → tracked in **#71** (schema migration, its own Gate).
- The toStringAsFixed display-precision debt → **#70**.

## Verified current state (`main` @ HEAD)

Two validators, different nesting depths, nearest common ancestor `match /groups/{groupId}` (line 167):
- `validEventSettlementBase` — `security/firestore.rules:486`, inside `groups/{gid}/events/{eid}/{module}/{docId}` (module match line 384).
- `validGroupSettlementBase` — `security/firestore.rules:669`, inside `groups/{gid}/settlements/{settlementId}` (match line 668).

Primitives the shared core needs are **all top-level** (visible everywhere): `nullableString:14`, `validCurrency:48`, `positiveInt:52`.

### The 9 shared predicates are identical between the two validators

The *predicates* below are identical (verified by Gate). They are interleaved with scope-specific lines inside each range, so cite predicates, not ranges: event = lines 502,503,506,507,508,509,510,511,512 (504-505 are the event participant checks, which stay scope-specific); group = lines 690,691,695,696,697,698,701,702,703 (692-694 scope/member checks and 699-700 display-name checks stay scope-specific).

```
data.createdBy is string
&& data.createdBy.size() > 0
&& data.payerParticipantId != data.recipientParticipantId
&& positiveInt(data.amountFils)
&& validCurrency(data.currency)
&& nullableString(data.note)
&& data.isDeleted is bool
&& (data.deletedAt == null || data.deletedAt is string)
&& data.settledAt is string
```

### What stays scope-specific (must NOT move into the core)

| Concern | Event (`:486`) | Group (`:669`) |
|---|---|---|
| `keys().hasOnly([...])` | 11 keys (no groupId/scope/payerName/recipientName) | 15 keys |
| doc-id check | `data.id == docId` | `data.id == settlementId` |
| parent-id check | `data.eventId == eventId` | `data.groupId == groupId` **and** `data.eventId == groupId` (sentinel) |
| scope literal | — | `data.scope == 'group'` |
| participant set | `... in participants()` (385) | `... in groupData(groupId).memberIds` |
| display names | — | `isValidNullableDisplayName(payerName/recipientName)` (699-700) |

`participants()` (385) is scoped to the event module block, so it can NOT be referenced from the core — another reason the participant check stays in each validator.

## Proposed change

1. Add at top-level (near `positiveInt`, ~line 56), so both blocks can call it:

```
// Shared settlement predicates. Scope-specific shape (keys, participant set,
// scope, names, eventId/groupId binding) stays in the per-scope validators.
function validSettlementCore(data) {
  return data.createdBy is string
    && data.createdBy.size() > 0
    && data.payerParticipantId != data.recipientParticipantId
    && positiveInt(data.amountFils)
    && validCurrency(data.currency)
    && nullableString(data.note)
    && data.isDeleted is bool
    && (data.deletedAt == null || data.deletedAt is string)
    && data.settledAt is string;
}
```

2. `validEventSettlementBase` → `keys().hasOnly([...11]) && data.id == docId && data.eventId == eventId && data.payerParticipantId in participants() && data.recipientParticipantId in participants() && validSettlementCore(data)`.

3. `validGroupSettlementBase` → `keys().hasOnly([...15]) && data.id == settlementId && data.groupId == groupId && data.eventId == groupId /* sentinel, see #71 */ && data.scope == 'group' && data.payerParticipantId in groupData(groupId).memberIds && data.recipientParticipantId in groupData(groupId).memberIds && isValidNullableDisplayName(data.payerName) && isValidNullableDisplayName(data.recipientName) && validSettlementCore(data)`.

4. Inline comment on the `data.eventId == groupId` line documenting the sentinel and linking #71.

## Behavior-preservation argument

The 9 moved predicates are identical (verified above); every scope-specific predicate stays in place; no predicate is added or dropped. `validSettlementCore` calls only top-level primitives + reads on the passed `data`. Net rule evaluation is unchanged for every create/update on both collections. The test suite (existing + new) must stay **green before and after** — that is the proof.

**Scope of the live proof (Gate [P3]):** settlement *updates* are already append-only/denied (group `allow update: if false` @738; event module routes updates to `validExpenseUpdate`, not the settlement update validator, ~@570). So the meaningful preservation surface is settlement **creates** + rules compile safety. `validEventSettlementUpdate`/`validGroupSettlementUpdate` still call the Base validators, so the refactor flows through them too, but they sit behind deny rules — existing update-denied tests (797-823, 840-890) must stay green as deny-characterization.

## Test plan — `functions/test/firestore-rules-publish-readiness.test.ts`

Reuse existing factories: `validSettlement()`, `validGroupSettlement()`, `seedEventSettlement()`, `seedGroupSettlement()`, `withoutField()`.

**Existing coverage (keep, must stay green):** valid create both scopes (776/780); participant-not-member→fail (event, 778); negative amount→fail (group, 782); createdBy stamping (786); creator/non-creator update & soft-delete denied (797-823, 840-866); create-without-createdBy→fail (825/868); delete denied (833/885); group update cannot mutate createdBy (876).

**New gap tests (write first, run green on current rules = characterization, re-run green after refactor):**
- Shared-core symmetry (assert both scopes reject identically):
  - `amountFils <= 0` → fail (add **event** case; group exists)
  - invalid `currency`: **non-string OR string length ≠ 3** → fail (both scopes). NOTE (Gate [P2]): `validCurrency` (rules:48) only checks `is string && size()==3` — a bogus 3-letter code like `'ZZZ'` PASSES. Do NOT assert `'ZZZ'` fails; it would fail against current rules and be a false characterization.
  - `payerParticipantId == recipientParticipantId` → fail (both scopes)
  - `note` wrong type (non-string/non-null) → fail (both scopes)
  - `settledAt` missing → fail (both scopes)
- Scope-shape (stays out of core, but touched by the edit):
  - extra/unknown key → fail (both scopes — proves `keys().hasOnly` intact)
  - group: `eventId != groupId` → fail (locks the sentinel before #71 touches it)
  - group: `scope != 'group'` → fail
  - group: invalid `payerName`/`recipientName` (control char / >32) → fail

## Verification

```bash
cd functions && npm test -- firestore-rules-publish-readiness   # Java 21 + emulator
# or full emulator run:
firebase emulators:exec --only firestore,auth 'cd functions && npm test'
```
- `test_rules/` and functions rules tests are referenced by `release_android.yml` + `readiness_check.yml`.
- No `flutter analyze` impact (rules + TS only); run functions ESLint.

## Gate

Touches `security/firestore.rules` → **`/codex` fresh-context review is mandatory before any edit** (Operating Contract).

**Status: PASSED** (codex consult, session `019e71f6`, 2026-05-29, high reasoning, read actual files). **Verdict: no [P1] — behavior-preserving.** Findings folded into this spec: [P2] invalid-currency test precision (validCurrency only checks string+len3); [P3] predicates-not-ranges wording; [P3] update paths are deny-gated so proof centers on creates. Clear to implement.

## Execution order (after Gate clears)

1. Add new gap tests → run → confirm green on **current** rules (characterization). Any red here = a behavior surprise to understand before refactoring.
2. Extract `validSettlementCore` + wire both validators + sentinel comment.
3. Re-run full rules suite → must be green (preservation proof).
4. Functions ESLint clean. Commit `refactor(rules): extract shared settlement validator (#48)`.
