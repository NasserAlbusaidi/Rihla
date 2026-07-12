# #71 — Replace the `eventId == groupId` sentinel on group settlements with an explicit representation

Spec author date: 2026-07-12. Branch: `refactor/71-settlement-scope-sentinel`.
Status: SPEC ONLY — no code written. Feeds fresh-context Gate rounds before implementation.
Gate category: **schema change with both a read-path and a write-path** (unconditional Gate per Operating Contract).

Issue: `tech-debt(rules): replace eventId==groupId sentinel on group settlements with explicit representation` (P3, `cluster:schema-debt`, `model:opus-4.8`). Two prior deferrals (2026-06-01, 2026-06-19) whose stated revisit condition — "revisit only if we are already touching the settlement model" — is now met by the surrounding settlement work (#1093/#929/#889).

---

## 0. TL;DR / chosen representation (two sentences)

Group-scoped settlements already carry an explicit `scope: 'group'` field **and** a `groupId` field on the wire; the `eventId: groupId` sentinel is a **third, redundant** encoding of the same fact that is written but **never compared anywhere** (no branch tests `eventId == groupId`). The migration is therefore: **stop writing the sentinel** (client `buildGroupSettlementDoc` + server `buildGroupReverseData`) and **stop requiring it** (drop `eventId` from `validGroupSettlementBase`'s `hasOnly` list and delete the `data.eventId == groupId` clause), keeping the model's existing absent-`eventId` read fallback as permanent legacy-doc tolerance — **no data backfill, no TS oracle change, no dedup-id change**.

---

## 1. Verified current state (every claim cited against live code this session)

### 1.1 The model already has the explicit fields

`lib/features/ledger/models/settlement_model.dart`:
- `scope` (String, default `'event'`) — line 20, 71, 144. `'event'` | `'group'`.
- `groupId` (String?, null for event settlements) — line 24, 72, 145.
- `tripId` (String) — line 7. `fromFirestore` (line 149-150):
  ```dart
  final tripId =
      data['eventId'] is String ? data['eventId'] as String : (groupId ?? '');
  ```
  So `tripId` reads `eventId` when present, else falls back to `groupId`. For a group doc it resolves to `groupId` **either way** (legacy sentinel `eventId == groupId`, or new absent-`eventId` → `groupId ?? ''`). **The read-path already tolerates the new shape.**

### 1.2 The sentinel is WRITTEN in exactly two places

- **Client** — `lib/features/groups/services/group_settlement_service.dart:104`, inside `buildGroupSettlementDoc` (the single source of the group-settlement write shape, #929):
  ```dart
  'eventId': groupId, // sentinel per RESEARCH Pitfall 3 — group settlements have no eventId
  'scope': 'group',   // line 105 — the real, explicit discriminator
  'groupId': groupId, // line 103
  ```
  Reached by `addGroupSettlement` (direct group settle-up) and by `stageDecomposedSettleUp`'s residual leg (line 281).
- **Server (Admin SDK)** — `functions/src/callables/shared/settlementCorrection.ts:217`, inside `buildGroupReverseData` (the offsetting-row builder for #283/#889 group-scope corrections):
  ```ts
  groupId,
  eventId: groupId,   // line 217 — sentinel
  scope: 'group',     // line 218
  ```

Event settlements write a **real** event id — `settlement_service.dart:105` (`'eventId': eventId` in `buildSettlementDoc`) and the correction reverse `settlementCorrection.ts:193` (`eventId` param). These are NOT sentinels and are **out of scope**.

### 1.3 The sentinel is NEVER compared — scope is carried by `scope` + collection path

Exhaustive sweep (Dart `lib/` + TS `functions/src/`) found **no** `eventId == groupId` / `tripId == groupId` branch anywhere. Scope is distinguished by:
- **Collection path** on the server: event settlements load from `eventDoc.ref.collection('settlements')` (`groupNetBalance.ts:562`), group settlements from `groupRef.collection('settlements')` (`groupNetBalance.ts:574`); trigger routing is path-based (`balanceAggregator.ts:253-254` event vs `:268-270` group).
- **Stream/provider** on the client: event settlements come from `SettlementService.watchSettlements` / `getSettlements` (event path); group settlements from `GroupSettlementService.watchGroupSettlements` (group path). `group_balance_provider.dart:341` buckets only `allEventSettlements` by `settlement.tripId`; group settlements never enter that map (folded globally at `:353-378`, reading only payer/recipient/amount/currency).
- **The `scope` field** in the correction callables' inputs (`correctSettlement.ts:66`, `correctLogicalSettleUp.ts:123/129` — determined by which collection the original was found in, then stamped).

### 1.4 The rules read-path (citation refreshed)

`security/firestore.rules` — `validGroupSettlementBase` at line 1192 (issue cited `:708`; **stale** — the file grew, the clause is now at **`:1223`**):
- `hasOnly([...])` list (lines 1199-1216) **includes** `'eventId'` (line 1202) — so `eventId` is a permitted key; combined with the value check below it is de-facto required.
- `data.id == settlementId` (1217), `data.groupId == groupId` (1218) — explicit group binding, already present.
- **`data.eventId == groupId`** (line 1223) — the sentinel clause, with an inline comment (1219-1222) naming **#71** as the migration tracker.
- `data.scope == 'group'` (line 1224) — the explicit discriminator, already present.
- Group settlement match block: `allow read: if isGroupMember(groupId)` (1271, **no field validation on read**); `allow create: if validGroupSettlementCreate()` (1272); `allow update: if false` (1274); `allow delete: if false` (1276) — **append-only**.

`validEventSettlementBase` (line 928) requires `data.eventId == eventId` (line 952) against a **real** route event id — untouched by this migration.

### 1.5 The TS oracle + aggregator are eventId-agnostic (parity is safe)

- `groupNetBalance.ts` settlement folds read only `s.currency`, `s.amountFils`, `s.payerParticipantId`, `s.recipientParticipantId`: event fold `:446-467`, group fold `:719-733`. **No `s.eventId` read.**
- `deleteGroup.ts:275`, `leaveGroup.ts:99`, `removeMember.ts:139` all go through `recomputeNet` → same path-based, eventId-agnostic snapshot.
- `balanceAggregator.ts` `SETTLEMENT_BALANCE_KEYS` (`:181-187`) = `['amountFils','currency','payerParticipantId','recipientParticipantId','isDeleted']` — `eventId`/`scope` absent (an eventId change wouldn't even trigger a recompute).
- `settlementNotifier.ts` — the param confusingly named `eventId` (line 38) is `event.id` (the **CloudEvent id**, passed at `:105/:116`), used only in the dedupe key; the FCM `payload.eventId` (`:83`) is `event.params.eid` (path segment, event scope only). **Neither reads the settlement doc's `eventId` field.**

### 1.6 The deterministic dedup id (#1093) does NOT read the sentinel

`SettlementService.deterministicSettlementId` (`settlement_service.dart:139-158`) hashes `['sd1', scopeKey, payer, recipient, currency, fils, pairEpoch]` — **no `eventId`**. `eventId` enters only via the caller-built `scopeKey` string:
- event: `scopeKey: 'event:${groupId}:${eventId}'` (`settle_up_screen.dart:863`) — a route param, not a doc field.
- group standalone: `scopeKey: 'group:${groupId}'` (`group_settle_up_screen.dart:1033`) — **no eventId**.
- decompose link id: `scopeKey: 'gsu:${groupId}'` (`group_settle_up_screen.dart:848`) — **no eventId**.
- `decomposeLegSettlementId(groupSettleUpId, eventId)` (`:182`) uses `leg.eventId` (an event-doc id from `eventOrder`), and `decomposeResidualSettlementId(groupSettleUpId)` (`:187`) uses no eventId.

**Consequence for principle 6:** dropping the wire `eventId` from group docs changes **zero** dedup ids — identical logical settlements still derive identical ids, so the append-only `allow update: if false` idempotency guard (#1093) is unaffected.

---

## 2. Chosen representation + rejected alternatives

### 2.1 CHOSEN — Option A: drop `eventId` from group-settlement docs; rely on existing `scope: 'group'` + `groupId`

Group scope is fully and non-redundantly represented by two fields that **already exist on the wire, in the model, and in the rules**: `scope == 'group'` and `groupId == <gid>`. The sentinel is deleted from both write builders and de-required in the rules. The model's absent-`eventId` fallback (§1.1) becomes the permanent read-path tolerance for legacy sentinel docs.

Why this is the right call:
- Smallest diff that actually removes the overload from the **wire** (the issue is a wire-format sentinel).
- No new field, no new `SplitMode`-style taxonomy, no model class fork.
- No dedup-id change (§1.6), no oracle/parity change (§1.5), no data backfill (§4).
- Rules expression count **decreases** (§3.2) — zero #723 pressure.

### 2.2 REJECTED — Option B: keep `eventId` present but set it to explicit `null` on group docs

Rules would read `data.eventId == null`. Rejected: `null` is still the **same field carrying a non-value** — it re-encodes "n/a" in the overloaded field instead of removing the overload. It keeps `eventId` in the `hasOnly` list (no wire-shape simplification), adds rather than removes a rules expression, and leaves the model's `data['eventId'] is String` guard reading a present-but-null key (`is String` is false → same `groupId` fallback, so no read benefit). More surface, less cleanup. No.

### 2.3 REJECTED — Option C: separate `GroupSettlement` model / collection-typed class

Rejected as wildly disproportionate. `Settlement.fromFirestore` is a **single total money-decode** shared by both scopes (the #928 totality invariant, `malformed_doc_fencing_test.dart` test 7); the oracle folds both scopes through one decode by path; `delete_group_balance_parity_test.dart` pins byte-for-byte parity across both. A second model would fork the totality invariant and the parity contract for the sake of removing one redundant key. No.

### 2.4 REJECTED — Option D: backfill/rewrite existing prod group-settlement docs to remove `eventId`

Rejected (see §4). Group settlements are append-only (`allow update/delete: if false`), read-gated by membership only (no field validation on read), the model tolerates the sentinel, and the oracle is path-based — legacy docs are inert and correct forever. A backfill is a destructive batch write over **money docs** for zero behavioral gain, exactly the risk class the Operating Contract's "destructive batch sweeps" rule warns against.

---

## 3. Exact wire format + rules diff

### 3.1 Field-level wire format, before → after

Enumerated from the type (`settlement_model.dart`, all 17 fields + derived getter), not memory. Wire column = Firestore key.

| Model field | Wire key | Event settlement | Group settlement BEFORE | Group settlement AFTER |
|---|---|---|---|---|
| `id` | `id` | present | present | present |
| `tripId` | `eventId` | real event id | **`= groupId` (sentinel)** | **ABSENT** |
| — | `groupId` | absent | present (`= gid`) | present (`= gid`) |
| `scope` | `scope` | absent (→ default `'event'`) | `'group'` | `'group'` |
| `payerParticipantId` | `payerParticipantId` | present | present | present |
| `recipientParticipantId` | `recipientParticipantId` | present | present | present |
| `amount` | `amountFils` (int subunits) | present | present | present |
| `currency` | `currency` | present | present | present |
| `note` | `note` | present/null | present/null | present/null |
| `payerName` | `payerName` | present/null | present/null | present/null |
| `recipientName` | `recipientName` | present/null | present/null | present/null |
| `isDeleted` | `isDeleted` | present | present | present |
| `deletedAt` | `deletedAt` | present/null | present/null | present/null |
| `settledAt` | `settledAt` (ISO8601) | present | present | present |
| `createdBy` | `createdBy` | present | present | present |
| `groupSettleUpId` | `groupSettleUpId` | omit-when-null | omit-when-null | omit-when-null |
| `correctionOfSettlementId` | `correctionOfSettlementId` | Admin-only, omit-when-null | Admin-only, omit-when-null | Admin-only, omit-when-null |

**Only one cell changes:** the group-settlement `eventId` key goes from `= groupId` to **absent**. Everything else is byte-identical. The `tripId` model field is unchanged in value (still resolves to `groupId` for group docs, via the fallback).

### 3.2 `firestore.rules` diff sketch (`validGroupSettlementBase`, ~line 1192)

Two edits, both **removals**:

1. Remove `'eventId'` from the `hasOnly` list (delete line 1202) — group docs may no longer carry the key (strict end-state). New shape rejects a carried `eventId` (extra key → `hasOnly` fails).
2. Delete the sentinel clause + its comment (lines 1219-1223, the `&& data.eventId == groupId` conjunct).

Resulting invariant carried by what remains: `data.groupId == groupId` (1218) `&& data.scope == 'group'` (1224). The doc is provably group-scoped without the sentinel.

**Expression-budget reasoning (#723):** this path is `match /groups/{gid}/settlements/{id}` with `allow create: if validGroupSettlementCreate()` and `allow update/delete: if false`. It is **entirely separate** from the event `allow update` OR-chain that sits near the ~1000-expression ceiling. Both edits are **deletions** (one fewer `hasOnly` entry, one fewer equality) → the group create path's expression count **strictly decreases**. We are NOT adding to `validEventBase`, the event OR-chain, or any `get()`-bearing branch. Zero ceiling risk. (If the Gate prefers a tolerant intermediate — see §5 — that variant adds at most one cheap `!('eventId' in data)` disjunct, still far from the ceiling and still off the event path.)

### 3.3 Client write-path change

`lib/features/groups/services/group_settlement_service.dart` — delete line 104 (`'eventId': groupId,`) from `buildGroupSettlementDoc`. No other change (both `addGroupSettlement` and `stageDecomposedSettleUp` residual leg flow through this builder — one deletion covers both). `buildSettlementDoc` (event legs) is untouched.

### 3.4 Server write-path change

`functions/src/callables/shared/settlementCorrection.ts` — delete line 217 (`eventId: groupId,`) from `buildGroupReverseData`. `buildEventReverseData` (`:193`, real event id) is untouched. (Admin SDK bypasses rules, so this is a **consistency** change, not a correctness one — see §5 ordering.)

### 3.5 Model read-path change

`lib/features/ledger/models/settlement_model.dart` — **no code change required**; the `data['eventId'] is String ? ... : (groupId ?? '')` fallback (line 149-150) already yields the correct `tripId` for absent-`eventId` group docs. Update the stale inline comment (lines 147-148) to state the new invariant ("group settlements no longer carry `eventId`; legacy sentinel docs still tolerated") and add a regression test (§6). **The fallback is load-bearing legacy tolerance — do not remove it.**

---

## 4. Migration / compat strategy

**Recommendation: read-path tolerance, PERMANENT. No data backfill.**

- **Existing prod group-settlement docs** carry `eventId == groupId`. They are append-only (`allow update/delete: if false`), read-gated by membership only (no field validation on read), decoded by the sentinel-tolerant model, and folded by the path-based oracle. They remain **valid and money-correct forever** with zero action.
- **New group-settlement docs** (post-client-ship) omit `eventId`; decoded via the same fallback; folded identically.
- **Coexistence** of legacy + new docs in one `groups/{gid}/settlements` collection is a non-event: both decode to the same `Settlement` shape (`scope: 'group'`, `groupId: gid`, `tripId: gid`) and fold identically (oracle reads neither `eventId` nor `scope`).
- Per Operating Contract "**No real users yet → server changes deploy freely**": there are no in-the-wild queued offline writes and no client-compat gating obligation. The only client that could still emit the sentinel is the developer's own unmigrated build (§5).

The permanent tolerance is the model fallback (§3.5), **not** a rules relaxation — rules never validate reads of these docs.

---

## 5. Deploy order

`functions/` (settlementCorrection) **and** `security/` (rules) both change → backend deploy required; `lib/` changes → client ship. Run through `tool/pending_deploy.sh` / the `deploy-ceremony` skill; the `backend-deployed` tag advances only on a successful deploy + prod-state verify; record in `docs/DEPLOY-LEDGER.md`.

**Recommended sequence (strict end-state, backend-first):**
1. **Backend** (rules strict per §3.2 + functions per §3.4), deployed together via the ceremony, tag advances.
2. **Client** (§3.3 + §3.5), shipped immediately after.

Ordering rationale, spelled out:
- The rules edit REMOVES a required key. After the strict deploy, an **old client** creating a group settlement (still carrying `eventId`) is **rejected** (extra key → `hasOnly` fails). With no users, the only affected client is the developer's own unmigrated build during the window between backend deploy and client ship — acceptable, and minimized by shipping client immediately.
- The `buildGroupReverseData` (Admin SDK) change is order-insensitive for correctness (Admin bypasses rules; the model tolerates a present or absent `eventId` on the reverse doc either way). Bundle it with the backend deploy purely for cleanliness.
- Legacy prod docs need no deploy coordination (append-only, read = membership-only).

**Optional zero-risk variant (belt-and-suspenders, if the Gate wants no window at all):** deploy rules **tolerant** first — keep `eventId` in `hasOnly` but replace `data.eventId == groupId` with `(!('eventId' in data) || data.eventId == groupId)` so BOTH shapes create-validate; ship client (stops writing the key); then a follow-up rules tightening removes `eventId` from `hasOnly`. Costs one extra deploy and one cheap disjunct; given the no-users latitude the strict one-shot above is preferred, but this variant is fully specified so the Gate can choose.

---

## 6. Test plan (RED-first)

Emulator command discipline: **never bare `npm test`** (hangs, no emulator). Use `cd functions && npm run test:emulator -- <file> -t "<name>"`.

### 6.1 Rules (emulator) — `functions/test/firestore-rules-publish-readiness.test.ts`

- **RED-first (new, fails before rules edit):** a group-settlement create that **omits `eventId`** must SUCCEED. Today it is denied (missing required `data.eventId == groupId`). Add `withoutField(validGroupSettlement({...}), 'eventId')` → `assertSucceeds`. Paste failing-before output.
- **RED-first (new):** a group-settlement create that **carries `eventId`** (any value, incl. `= groupId`) must FAIL after the strict edit (`hasOnly` rejects the extra key). Add `validGroupSettlement({ eventId: 'g1' })` → `assertFails`. (Under the tolerant variant §5, this case instead asserts SUCCEEDS for `eventId == groupId` and FAILS for a mismatched value — pick per chosen variant.)
- **Update the helper:** `validGroupSettlement` (line 214-233) — drop `eventId: 'g1'` (line 218). This will ripple through every `seedGroupSettlement`/create assertion in the file; re-green them.
- Same helper edit in `functions/test/settlementIdempotency.rules.test.ts` (`validGroupSettlement`, ~line 132-140) — drop `eventId`; the #1093 idempotency describe (`group scope`, line 217+) must stay green (dedup id unchanged, §1.6).
- Publish-readiness cross-guard: `functions/test/firestore-rules-publish-readiness.test.ts` must stay green (the note-update-fails / append-only pins are unaffected).

### 6.2 TS oracle / aggregator parity — must stay GREEN unchanged

- `functions/test/callables/groupNetBalance.test.ts`, `functions/test/callables/deleteGroup.test.ts`, `functions/test/callables/removeMember.test.ts`, `functions/test/callables/correctLogicalSettleUp.test.ts` — no source change to the oracle; these prove eventId-agnosticism. If any seeds a group settlement with `eventId`, drop it and confirm net is unchanged.
- `functions/test/decomposed-settleup-batch.test.ts` — residual leg no longer carries `eventId`; assert the batch still commits and folds identically.

### 6.3 Dart round-trip / model — `test/unit/settlement_service_test.dart`, `test/unit/group_settlement_service_test.dart`, `test/unit/malformed_doc_fencing_test.dart`

- **RED-first (new):** a group settlement written WITHOUT `eventId` round-trips to `tripId == groupId`, `scope == 'group'`, `groupId == groupId`. (Add to `group_settlement_service_test.dart` — asserts `buildGroupSettlementDoc` output has no `eventId` key and `fromFirestore` still yields the right `tripId`.)
- **Legacy tolerance (new):** a hand-built legacy doc WITH `eventId == groupId` still round-trips identically (same `tripId`, `scope`, `groupId`) — pins §4 permanent tolerance. Add to `malformed_doc_fencing_test.dart` alongside test 7.
- `test/unit/deterministic_settlement_id_test.dart` — must stay GREEN (id unchanged, §1.6); optionally add an assertion that removing `eventId` from the doc does not change the derived id.

### 6.4 Balance parity — `test/unit/delete_group_balance_parity_test.dart` + `test/unit/group_balance_provider_test.dart` + `test/unit/balance_aggregate_parity_test.dart`

- Must stay GREEN. If any fixture seeds a group settlement with `eventId`, drop it; net must be byte-identical (proves the client↔server oracle parity is untouched).

### 6.5 Full suites

`flutter analyze` clean; `flutter test`; `cd functions && npm run test:emulator` targeted files above. 80% coverage floor holds (only deletions + a few new tests).

---

## 7. Verification principles (Operating Contract §"Verification principles") — run and reported

1. **Classify every callsite on the shared read/write path (INBOUND / OUTBOUND / BOTH).**
   - `buildGroupSettlementDoc:104` — **OUTBOUND** (feeds the Firestore write). Sentinel deleted here.
   - `buildGroupReverseData:217` — **OUTBOUND** (Admin write). Sentinel deleted here.
   - `settlement_model.dart:149-150` (`tripId` fallback) — **INBOUND** (deserialize/display only; `toJson` at :110 is the legacy Supabase-era serializer, never writes `eventId` to Firestore — confirmed the Firestore write shape is built solely by the two service builders). Kept as legacy tolerance.
   - `group_balance_provider.dart:341` — **INBOUND** (buckets event settlements by `tripId` for display/fold; group settlements excluded). Unaffected: for group docs `tripId` still `== groupId`.
   - `group_settle_up_screen.dart:96` — reads `expense.tripId` (an **Expense**, not a settlement) → not a settlement callsite at all.
   - **Finding:** the only OUTBOUND uses of the sentinel are the two builders; both are edited. No INBOUND surface persists an `eventId` derived from a group doc.

2. **Verify every concrete claim against code, not docs.** Done throughout §1 — every file:line re-read this session. Notably corrected the issue's stale `firestore.rules:708` citation to the live **`:1223`**, and confirmed the issue's `settlement_model.dart:100-104/:133` citations no longer match (the model was refactored; the write shape moved to the service builders).

3. **Trace one read-path per write-path.** Write = `buildGroupSettlementDoc` (drops `eventId`). Named reader after the change: `Settlement.fromFirestore` → `tripId = groupId ?? ''` → `group_balance_provider.dart` fold + `settle_up_page_body` display. Server reader: `recomputeNet` group fold (`groupNetBalance.ts:719-733`) — reads payer/recipient/amount/currency, not `eventId`. Both read paths produce identical output pre/post.

4. **Enumerate fields from the type, not memory.** Done — §3.1 table lists all 17 `Settlement` fields + the derived `isMarkedCorrection` getter, mapped to wire keys, from `settlement_model.dart` lines 6-57.

5. **Spell out data contracts.** Exact `hasOnly` key lists quoted (group `:1199-1216`, event `:935-950`); exact builder maps quoted (`group_settlement_service.dart:101-121`, `settlement_service.dart:103-122`, `settlementCorrection.ts:188-235`); exact rules clauses quoted (`:1217-1236`).

6. **Verify arithmetic decomposition.** N/A to a monetary aggregate here (no field is being summed), but the adjacent risk IS money: the dedup id and the oracle net. Verified both are **invariant** under the change — dedup id excludes `eventId` (§1.6), oracle net excludes `eventId` (§1.5). Explicitly: `net = f(payer, recipient, amountFils, currency, path)`; removing `eventId` from a group doc changes no argument to `f`.

7. **Adversarial pass on an ORTHOGONAL axis.** The fix is on the **schema-identity** axis ("does the `eventId` field exist on a group doc"). Orthogonal worked example on the **money-flow + time** axis (§8).

---

## 8. Adversarial worked example (orthogonal axis: money-flow across a legacy/new + decompose mix)

Group `g` (currency OMR, scale 1000), members A, B. Timeline crosses the migration:

**T0 (pre-migration, old client):** A group settle-up A→B for OMR 3.000 is recorded as a **legacy** group settlement doc `L`: `{groupId: g, eventId: g (sentinel), scope: 'group', payer: A, recipient: B, amountFils: 3000, currency: OMR, isDeleted: false}`.

**T1 (post-migration, new client):** A #929 **decomposed** settle-up A→B across 3 events (e1 OMR 1.000, e2 OMR 0.500, residual OMR 0.500) writes 2 event-settlement legs (real `eventId` e1/e2 — untouched) + 1 residual **group** doc `R`: `{groupId: g, scope: 'group', payer: A, recipient: B, amountFils: 500, currency: OMR}` — **no `eventId` key**.

**T2 (post-migration, >9-leg fallback):** A→B settle-up spanning 12 events exceeds `kMaxDecomposeLegsAtomic (=9)`, so the screen pre-gate routes it to a **single** `addGroupSettlement` for OMR 2.000: group doc `S` `{groupId: g, scope: 'group', payer: A, recipient: B, amountFils: 2000, currency: OMR}` — **no `eventId` key**.

Now the `groups/g/settlements` collection holds `{L (sentinel), R (no eventId), S (no eventId)}` — a mixed aggregate.

**Assertion 1 (oracle):** `recomputeNet` loads all three from `groupRef.collection('settlements')` and folds each into the OMR bucket by payer/recipient/amount (`groupNetBalance.ts:719-733`), reading `eventId` on **none** of them. Net contribution to B from group settlements = 3.000 + 0.500 + 2.000 = **5.500** (A owes-down by the same). Byte-identical to what the pre-migration oracle would have computed for the same three payments (it never read `eventId` either). `delete_group_balance_parity_test.dart` and `balance_aggregate_parity_test.dart` stay green.

**Assertion 2 (dedup / idempotency):** `S`'s id derives from `scopeKey: 'group:g'` + pair-epoch (`group_settle_up_screen.dart:1033`); `R`'s from `decomposeResidualSettlementId(gsu)` — neither reads `eventId`. A retry of either from a second device derives the **same** id and collides against `allow update: if false` (#1093). Removing the sentinel changed no id. `settlementIdempotency.rules.test.ts` group-scope describe stays green.

**Assertion 3 (rules coexistence):** `L` was created under old rules and is now inert (append-only, read = membership-only) — the new strict rules never re-validate it. `R` and `S` create-validate under the new rules via `scope == 'group'` + `groupId == g`, with **no** `eventId` key (passes the tightened `hasOnly`). A hostile client re-submitting `L`'s exact shape (carrying `eventId: g`) is now **rejected** (extra key) — a strictly tighter surface, not a regression.

**Assertion 4 (correction):** A #283 correction of `S` runs `buildGroupReverseData` → writes an offsetting group doc with **no** `eventId` (post §3.4), `correctionOfSettlementId: S.id`. `fromFirestore` decodes it (fallback → `tripId == g`); the reverse nets B down by 2.000. `correctLogicalSettleUp.test.ts` stays green.

This exercises money conservation, legacy/new temporal coexistence, the decompose path, the >9-leg carve-out, idempotency, and corrections — all orthogonal to "does the field exist," and each lands on the same invariant: **the sentinel was write-only dead weight; removing it moves no money and breaks no dedup.**

---

## 9. Rollback story

- **Pre-deploy:** revert the branch. Nothing shipped.
- **Post-backend-deploy, pre-client:** the strict rules reject a carried `eventId`. Rollback = redeploy the previous rules (tag-tracked; `backend-deployed` moves back) via the ceremony. Legacy + new docs both still read fine (model tolerance is forward-and-backward compatible), so a rules rollback is non-destructive — no data is stranded.
- **Post-client-ship:** to roll the client back, the OLD `buildGroupSettlementDoc` would re-add the sentinel — which the strict rules reject. So a client-only rollback requires ALSO rolling rules back to tolerant/legacy. Because the model tolerates both shapes in both directions, any (rules, client) rollback combination reads correctly; the only invalid combination is (strict rules, old client writing the sentinel) → group-settlement creates denied (loud, not silent-corrupt). **No monetary rollback risk** — no data was mutated, only the write shape and the create gate.
- **Data:** never touched (no backfill), so there is no data rollback.

---

## 10. Open questions for the Gate

1. **Strict one-shot vs tolerant two-phase (§5).** No-users latitude permits strict-in-one-deploy; the tolerant variant eliminates even the developer's own deploy-window at the cost of an extra deploy + a follow-up tightening. Which does the Gate want? (Spec defaults to strict; tolerant fully specified.)
2. **`buildGroupReverseData` (§3.4) is Admin-only.** Bundling it with the backend deploy is cleanliness, not correctness. Confirm the Gate wants the sentinel gone from the correction path too (spec assumes yes — otherwise the "eliminate the sentinel" goal is only ~half done, and a future reader would re-discover the overload on correction docs).
3. **`tripId` model overload lingers.** After this change the wire no longer carries the sentinel, but the Dart `Settlement.tripId` field still resolves to `groupId` for group docs. Is that in scope for #71 (rename `tripId`→something scope-neutral, or expose `eventId?`/`groupId` distinctly) or a separate follow-up? Spec treats it as **out of scope** (the issue is the wire sentinel; `tripId` is a client-model convenience with no persistence). Flagging so the Gate can confirm the boundary.
4. **Stale inline comments to sweep.** `firestore.rules:1219-1222` (names #71), `settlement_model.dart:147-148`, `group_settlement_service.dart:84` doc-comment ("carries the `eventId: groupId` sentinel"), and the RESEARCH.md "Pitfall 3" reference all describe the sentinel. Confirm the implementation PR updates each (not just the code) so the doc trail doesn't re-teach the overload.
