# #814 — Group-Activity Metadata Value-Domain Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden `validGroupActivityCreate` (`security/firestore.rules`) so a client-writable group-activity doc can no longer carry forged metadata values that the display layer must defend against — `amountFils: NaN`, negative fils, garbage currencies, non-string names.

**Architecture:** Rules-only change (plus emulator tests). A new `validActivityMetadata(md)` helper is called from `validGroupActivityCreate` after the existing `metadata is map` check. Known keys get absent-or-typed constraints via the single-reference `map.get(key, default)` pattern (#723); unknown keys stay opaque; the map is key-count bounded. No client, model, or Functions code changes — the client display half already shipped in #815/#816.

**Tech Stack:** Firestore security rules; `@firebase/rules-unit-testing` via the Java-21 emulator runner (`tool/run_firebase_emulator_tests.sh`).

**Issue:** #814 (Gate-category: `security/firestore.rules`). Refs sweep #192/#193/#194.

---

## Scope decisions (locked)

1. **Rules-only.** The issue's "client belt-and-braces" halves are already merged:
   - `activityAmount` guards non-finite `amountFils` (`isFinite`, PR2 #815) — `lib/features/activity/utils/activity_display.dart:120`
   - `_coerceLegacyAmount` guards non-finite legacy `amount` num (PR3 #816) — `activity_display.dart:145`
   - `_metadataString` type-guards `eventName`/`memberName`/`memberAction` (PR3 #816) — `activity_display.dart:32-35`
2. **Constraints (absent-or-valid; absent always passes):**
   - `amountFils` → `is int && >= 0`. Rules `is int` rejects doubles including NaN/±Inf. Negative fils have no legitimate writer (server fan-in writes positive expense amounts; clients never write this key).
   - `currency` → in the existing `validCurrency` allow-list (`firestore.rules:75-77`).
   - `amount` (legacy decimal-units) → `is string`. The only live client writer sends `amount.toString()` (`group_settle_up_screen.dart:891, :1032`); num amounts exist only in legacy *docs* (read path), never in new creates. This closes the `Decimal.parse(NaN)` forge at the source for new docs.
   - `eventName`, `memberName`, `memberAction` → `is string` (the PR3 round-2 finding: `eventName: 42` passed rules).
   - `metadata.size() <= 16` keys — bounded-opaque, same spirit as `splitExplanation`'s `size()<=64`. Legit writers use ≤ 5 keys.
   - Everything else (`eventId`, `groupId`, `recipientId`, `expenseId`, future ids) stays opaque per the issue ("don't over-constrain ids").
3. **NOT in scope:** `description` free-text hardening (`validFreeText`) — separate follow-up if wanted; `timestamp` forgeability (pre-existing, display-ordering only); the type allow-list (untouched, so the `writeRateMonitor` expense_* skip coupling is unaffected — the monitor reads only `type`, `functions/src/triggers/writeRateMonitor.ts:135-136`).

## Verification-principles report (run while authoring)

- **P1 callsite classification:** metadata write-path = 5 client `logGroupEvent` sites, all OUTBOUND, shapes enumerated below; server writers (`expenseAuditLogger` fan-in, `leaveGroup`/`removeMember` callables) are Admin SDK → rules-exempt → unaffected. Read-paths are INBOUND display-only (`activity_display.dart` helpers → both activity screens). Verified by grep: no money math reads activity metadata (oracle `recomputeNet` and `balanceAggregator` never touch the activity collection).
- **P2 claims vs code:** `validGroupActivityCreate` at `security/firestore.rules:994-1024`; `validCurrency` at `:75-77`; `map.get(key, default)` precedent at `:193-194`; existing #808 rules-test block + `validGroupActivity` helper at `functions/test/firestore-rules-publish-readiness.test.ts:2681-2731`.
- **P3 read-path per write-path:** hardened `metadata` → `activityAmount`/`activityAmountCurrency`/`localizedGroupActivityText`/`activityMatchesQuery` → activity rows. Display behaviour unchanged (client guards stay — legacy docs predating the rules change still need them).
- **P4 fields from the type:** client-written metadata key universe enumerated from the 5 call sites (not memory): `group_settlement` = `{amount: String, recipientId: String, currency: String}`; `event_created`/`event_deleted` = `{eventId: String, eventName: String}`; `member_joined` = `{groupId: String}`. All pass the new constraints.
- **P5 exact contract:** see "Rules change" below — exact rules text, not a gesture.
- **P6 arithmetic decomposition:** N/A — no aggregate math on this surface.
- **P7 orthogonal adversarial axes:** identity (actorId already pinned `== request.auth.uid` — unaffected); time (timestamp forgeable `is string` — pre-existing, out of scope, noted); compat (current production client shapes verified to pass — see P4; also "no real users yet → deploy freely"); offline (queued client writes replay with the same shapes → pass); server (Admin SDK bypasses rules → fan-in `amountFils` writes unaffected).
- **1000-expression ceiling:** the activity create path is a standalone match block with no heavy OR-chain (`groupData` referenced once via `isGroupMember`/`groupAllowsClientWrites`, already present). Adding ~8 cheap expressions via `get()` single-reference is far from the ceiling; cheap gates stay first.

## Rules change (exact)

In `security/firestore.rules`, inside `match /activity/{activityId}` (before `validGroupActivityCreate`):

```
        // #814 — value-domain floor for client-forgeable metadata (spirit of
        // #192/#193/#194). Known keys are absent-or-typed via the single-
        // reference get() pattern (#723); ids and unknown keys stay opaque;
        // the map is key-count bounded. Server writers (expense_* fan-in,
        // member_left callables) use the Admin SDK and bypass this.
        function validActivityMetadata(md) {
          return md.size() <= 16
            && md.get('amountFils', 0) is int
            && md.get('amountFils', 0) >= 0
            && validCurrency(md.get('currency', 'OMR'))
            && md.get('amount', '') is string
            && md.get('eventName', '') is string
            && md.get('memberName', '') is string
            && md.get('memberAction', '') is string;
        }
```

And in `validGroupActivityCreate`, replace:

```
            && request.resource.data.metadata is map
```

with:

```
            && request.resource.data.metadata is map
            && validActivityMetadata(request.resource.data.metadata)
```

## Tests (RED first)

New `#814` tests appended to the existing #808 group-activity block in `functions/test/firestore-rules-publish-readiness.test.ts` (reuse `validGroupActivity(overrides)`; `metadata` goes in overrides). Table:

**assertFails (member context, `type: 'group_settlement'` unless noted):**
- `metadata: {amountFils: NaN}` (Node SDK serializes NaN as a double)
- `metadata: {amountFils: Infinity}`
- `metadata: {amountFils: 10.5}` (double)
- `metadata: {amountFils: -100}` (negative int)
- `metadata: {amountFils: 10500, currency: 'ZZZ'}` (unsupported currency)
- `metadata: {amount: 42}` (num where legacy contract is string)
- `metadata: {eventName: 42}`, type `event_created` (the PR3 round-2 forge)
- `metadata: {memberName: 42}` and `{memberAction: 42}`
- metadata with 17 keys (size bound)

**assertSucceeds:**
- the real settle shape `{amount: '12.500', recipientId: 'member', currency: 'OMR'}`
- the real event shape `{eventId: 'e1', eventName: 'Trip'}`, type `event_created`
- the real join shape `{groupId: 'g1'}`, type `member_joined`
- empty `metadata: {}` (all keys absent)
- opaque unknown key `{someFutureId: 'abc'}` (proves ids stay unconstrained)
- `{amountFils: 10500, currency: 'OMR'}` (a client writing the fan-in shape legitimately is fine — the type allow-list, not metadata, is what fences expense_* forgeries)
- Admin SDK (`withSecurityRulesDisabled`) can still write `member_left` with `{memberName: 42}`-style garbage (documents that server writes bypass this — regression-pins the fan-in path can't be broken by this change)

### Task 1: Write the failing rules tests

**Files:**
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (append `#814` tests after the WHOLE #808 block — i.e. after its Admin-SDK `expense_added` test, ~:2731 — not mid-block)

**Step 1:** Add the tests from the table above.
**Step 2:** Run: `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t "#814"`
Expected: all `assertFails` forgery tests FAIL (writes currently succeed — `metadata is map` accepts everything); `assertSucceeds` shape tests PASS.

### Task 2: Rules change (GREEN)

**Files:**
- Modify: `security/firestore.rules` (`match /activity` block, ~:993)

**Step 1:** Apply the exact rules change above.
**Step 2:** Re-run the `#814` scope: all pass.
**Step 3:** Run the FULL rules file (regression, incl. the #808 type tests and 1000-expr-sensitive expense/event paths): `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts`
Expected: green, no "maximum of 1000 expressions" errors anywhere.

### Task 3: Commit + PR

**Step 1:** Commit: `fix(rules): #814 value-domain floor for client-writable group-activity metadata` — commit body carries `Closes #814`.
**Step 2:** PR with `Spec:` line pointing at this doc; body carries `Closes #814`, RED evidence (pasted failing-before-fix output), and the follow-up note re `description`/`timestamp` (out of scope).
**Step 3:** `/automerge <N>` (Gate-category → fresh review + refuter).

### Post-merge

- Deploy ceremony (`deploy-ceremony` skill) — rules-only deploy; advances `backend-deployed`, records in `docs/DEPLOY-LEDGER.md`.
