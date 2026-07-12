# #71 — Remove the `eventId == groupId` sentinel from group-settlement docs

Spec v2, 2026-07-12. Branch: `refactor/71-settlement-scope-sentinel`.
Status: SPEC ONLY — no code written. Feeds fresh-context Gate review before implementation.
Gate category: **schema/wire-format change with both a read-path and a write-path** (unconditional Gate per Operating Contract).

Issue: `tech-debt(rules): replace eventId==groupId sentinel on group settlements with explicit representation` (P3, `cluster:schema-debt`). Two prior deferrals (2026-06-01, 2026-06-19) whose revisit condition — "revisit only if we are already touching the settlement model" — is met by the #1093/#929/#889/#1129 settlement work.

> **Baseline note (v2):** v1 of this spec was authored against pre-#1129 code and was invalidated by Gate round 1. **#1129 made settlement creates CALLABLE-ONLY**: `firestore.rules` hard-denies client settlement creates in BOTH scopes (`security/firestore.rules:1215-1222` group — "#1129: validGroupSettlementBase/Create/Update were DELETED … `allow create: if false`"; the event block at `:1022+` carries the parallel comment), the client-side doc builders (`buildGroupSettlementDoc`/`buildSettlementDoc`) and the Dart dedup-id helpers were deleted, and all settlement docs are now written by **Admin SDK Cloud Functions**. Every claim below is re-verified against this post-#1129 tree. The issue's own citations (`firestore.rules:708`, `settlement_model.dart:100-104/:133`) are stale — live locations below.

---

## 0. TL;DR / chosen representation (two sentences)

Group-scoped settlement docs carry `groupId` + `scope: 'group'` and additionally an `eventId: groupId` **sentinel** that is written by exactly two Admin-SDK builders but **compared/read by nothing** — every reader splits group-vs-event by **collection path**, the dedup ids never ingest it, and the client model already falls back to `groupId` when `eventId` is absent. The change is: **delete the `eventId: groupId` line from the two server writers** (`functions/src/callables/recordSettlement.ts:503` and `functions/src/callables/shared/settlementCorrection.ts:217`), keep the model's absent-`eventId` fallback as permanent legacy tolerance, and ship as a **functions-only deploy — there is NO rules change and NO client code change in this migration.**

> **Implementer warning — do NOT resurrect deleted validators.** There is no `validGroupSettlementBase`/`validEventSettlementBase`/`validSettlementCore` to edit anymore; `allow create: if false` (both scopes) is the #1129 end-state and stays byte-identical. Any "rules diff" for this migration is a regression. Admin SDK bypasses rules entirely, so the group-settlement wire shape is enforced only by the two builders and their tests.

---

## 1. Verified current state (all citations re-read this session against the post-#1129 tree)

### 1.1 Write path: the sentinel has exactly two writers, both Admin SDK

**Primary — `functions/src/callables/recordSettlement.ts`** (the single settlement-create path for both scopes; modes `'event' | 'group' | 'groupSettleUp'`, validated at `:148-150`):

```ts
// :495-510
const groupSettlementDoc = (id, fils, groupSettleUpId) => {
  const data: DocumentData = {
    id,
    groupId,
    eventId: groupId, // sentinel — group settlements have no event   ← :503, DELETE
    scope: 'group',                                                   // :504
    amountFils: fils,
    ...settlementBase,   // payer/recipient ids+names, currency, note,
                         // isDeleted:false, deletedAt:null, settledAt (ISO string), createdBy
  };
  if (groupSettleUpId != null) data.groupSettleUpId = groupSettleUpId;
  return data;
};
```

`groupSettlementDoc` is invoked at **two write sites**: mode `'group'` (`:563` — the aggregate cross-event settle, which is also the ONE remaining client routing fallback for a pure cross-event pair, see §8) and the `groupSettleUp` **residual leg** (`:579-582`). One deleted line covers both. The event builder `eventSettlementDoc` (`:483-494`) writes a **real** `eventId` and is untouched.

**Secondary — `functions/src/callables/shared/settlementCorrection.ts`** (`buildGroupReverseData`, `:211-235`, the #889 offsetting-row builder used by the `correctSettlement` and `correctLogicalSettleUp` callables):

```ts
// :215-218
id: newId,
groupId,
eventId: groupId,   // ← :217, DELETE
scope: 'group',
```

`buildEventReverseData` (`:188-208`) uses a real `eventId` param and is untouched.

**No other writer exists.** Clients write no settlement docs: `lib/features/groups/services/group_settlement_service.dart:101-112` (`addGroupSettlement`) and `:141-160` (`recordDecomposedSettleUp`) only invoke the `recordSettlement` callable and return its `RecordSettlementResult` — no local doc echo is constructed. Verified: `rg buildGroupSettlementDoc lib/` → 0 hits; `rg "'eventId':" lib/` on settlement paths → 0 write sites.

### 1.2 Read path: NOTHING reads the sentinel; scope is carried by collection path

Verified reader-by-reader:

- **TS oracle** `functions/src/callables/groupNetBalance.ts`: `rg -n eventId functions/src/callables/groupNetBalance.ts` → **zero hits**. Group vs event settlements split by **path** — event docs from `eventDoc.ref.collection('settlements')` (`:563`), group docs from `groupRef.collection('settlements')` (`:574`). The folds read only `currency`, `amountFils`, `payerParticipantId`, `recipientParticipantId` (event fold `:446-467`; group fold `:719-733`). `deleteGroup`/`leaveGroup`/`removeMember` and the #1129 outstanding-cap all consume this same oracle.
- **Aggregator** `functions/src/triggers/balanceAggregator.ts`: trigger routing is by document **path** (event T1 vs group T2 at `:269`); the diff-gate `SETTLEMENT_BALANCE_KEYS` (`:185-191`) = `['amountFils','currency','payerParticipantId','recipientParticipantId','isDeleted']` — `eventId` and `scope` both absent (an `eventId` change wouldn't even trigger a recompute).
- **Notifier** `functions/src/triggers/settlementNotifier.ts`: the param named `eventId` (`:38`) is the **CloudEvent id** (`event.id`, passed at `:105`/`:116`), used only in the FCM dedupe key; the payload's `eventId` (`:83`) is the **path segment** `event.params.eid` (event scope only). Neither reads the doc field.
- **Corrections** `functions/src/callables/correctLogicalSettleUp.ts`: `orig.scope` is **stamped from which collection the doc was found in** (`:123-130` — group-snapshot docs get `scope: 'group'`, event-snapshot docs get `scope: 'event'` + the path's `eventDoc.id`), never read from the doc. `correctSettlement.ts` takes `scope` as a request input (`:65-70`) and resolves the original by path. Neither reads doc `eventId`.
- **Client model** `lib/features/ledger/models/settlement_model.dart:149-150`:
  ```dart
  final tripId =
      data['eventId'] is String ? data['eventId'] as String : (groupId ?? '');
  ```
  For a group doc, `tripId` resolves to `groupId` **whether or not** the sentinel is present — the new shape decodes identically today; zero client change needed. **This fallback is load-bearing legacy tolerance; do not remove it.**
- **Client consumers of `tripId`**: `lib/features/groups/providers/group_balance_provider.dart:341` buckets only `allEventSettlements` (fed by the event-path stream `SettlementService.watchSettlements`); group settlements arrive via the separate group-path stream (`GroupSettlementService.watchGroupSettlements`) and are folded globally (`:353-378`, payer/recipient/amount/currency only). The client, like the server, discriminates by **stream (= collection path)**, never by field.

### 1.3 NEW verification (Gate round-1 requirement): `scope` is not load-bearing either — including for legacy docs that might lack it

`Settlement.scope` (the **doc field**) is **never read anywhere**: the only Dart references are the model's own default (`settlement_model.dart:71,144`); every other `scope` identifier in lib/ is an unrelated widget/enum parameter (`SettleUpPageBody.scope` `settle_up_page_body.dart:268`, `split_card.dart` `ExpenseScope`, …). On the server, corrections stamp scope from the collection (§1.2) and the oracle/aggregator never read it. So a hypothetical old group doc **lacking `scope`** decodes as `scope: 'event'` in the model (`:144`) and still behaves correctly everywhere, because every group-vs-event decision is made by path/stream. Consequence: the migration rationale does NOT depend on legacy docs carrying `scope`. The durable discriminator is the **collection path**; `scope` on the wire is self-description, and `groupId` additionally feeds the model's `tripId` fallback. We keep writing both (§3) and remove only the third, fully redundant `eventId`.

### 1.4 Deterministic dedup ids (#1093, server-side since #1129): sentinel-independent

Derivation lives in `functions/src/callables/shared/settlementIds.ts` (the Dart originals were **deleted** by #1129; byte-parity with pre-#1129 client-minted ids is pinned by golden vectors in `functions/test/callables/shared/settlementIds.test.ts`):
- `deterministicSettlementId` (`:35-47`) hashes `['sd1', scopeKey, payer, recipient, currency, amountFils, pairEpoch]` — **no doc field, no eventId**.
- `scopeKey` is built in `recordSettlement.ts:364-368` from **request params**: `event:<groupId>:<eventId>` / `group:<groupId>` / `gsu:<groupId>` — the two group scopes contain no eventId at all.
- `decomposeLegSettlementId(groupSettleUpId, eventId)` (`:52-54`) uses the **leg's** real event id from the request; `decomposeResidualSettlementId(groupSettleUpId)` (`:56-58`) uses none.

**Consequence:** removing the wire sentinel changes **zero** ids — identical logical settlements derive identical ids before and after, so the `tx.create`-fails-on-exists dedup and the `alreadyRecorded: true` idempotent-retry contract are unaffected.

### 1.5 Rules: nothing to change, on purpose

`security/firestore.rules:1214-1226` (group scope): `allow read: if isGroupMember(groupId)` — membership-only, **no field validation on read** — then `allow create: if false` (#1129), `allow update/delete: if false` (B3). Event scope parallel at `:1022+`/`:1048-1051`. `rg -n "sentinel|#71" security/firestore.rules` → 0 hits (the old comment naming #71 was deleted with the validator). **This migration touches zero rules lines**, so the #723 expression-ceiling analysis is moot by construction: no rules expression is added or removed anywhere.

---

## 2. Chosen representation + rejected alternatives

### 2.1 CHOSEN — drop `eventId` from group-settlement docs; keep `groupId` + `scope: 'group'`

Delete one line in each of the two Admin-SDK builders (§1.1). Group docs remain self-describing (`groupId`, `scope`), the model's fallback keeps legacy docs decoding identically, and every reader is already path-based. Smallest possible diff that removes the overloaded field from the wire; no new field, no rules edit, no data touch, no id/parity impact.

### 2.2 REJECTED — explicit `eventId: null` on group docs

Re-encodes "n/a" in the same overloaded field instead of removing it. The model's `data['eventId'] is String` guard treats present-null identically to absent (falls back to `groupId`), so there is zero read benefit — only a lingering key every future reader must know to ignore. No.

### 2.3 REJECTED — separate `GroupSettlement` model / doc type

`Settlement.fromFirestore` is a single **total** money-decode shared by both scopes (#928 totality invariant, `test/unit/malformed_doc_fencing_test.dart` test 7) and the oracle folds both scopes through one decode; forking the model forks the totality invariant and the client↔server parity contract to remove one redundant key. Disproportionate. No.

### 2.4 REJECTED — backfill/rewrite existing prod group docs to strip the sentinel

Settlements are append-only (`allow update/delete: if false`, both scopes), read-gated by membership only, decoded tolerantly, folded by path. Legacy docs are inert and money-correct forever; a backfill is a destructive batch write over money docs for zero behavioral gain — the exact risk class the Operating Contract's destructive-sweep rule exists for. No.

---

## 3. Exact change

### 3.1 Field-level wire format, before → after

Enumerated from the type (`settlement_model.dart:5-77`, all 17 fields + the derived `isMarkedCorrection` getter), cross-checked against the live builders (`recordSettlement.ts:471-510`, `settlementCorrection.ts:188-235`).

| Model field | Wire key | Event doc | Group doc BEFORE | Group doc AFTER |
|---|---|---|---|---|
| `id` | `id` | present | present | present |
| `tripId` | `eventId` | real event id | **`= groupId` (sentinel)** | **ABSENT** |
| `groupId` | `groupId` | absent | `= gid` | `= gid` (kept — feeds the `tripId` fallback) |
| `scope` | `scope` | absent (→ model default `'event'`) | `'group'` | `'group'` (kept — self-description; never read, §1.3) |
| `payerParticipantId` | `payerParticipantId` | present | present | present |
| `recipientParticipantId` | `recipientParticipantId` | present | present | present |
| `amount` | `amountFils` (int subunits) | present | present | present |
| `currency` | `currency` | present | present | present |
| `note` | `note` | present/null | present/null | present/null |
| `payerName` | `payerName` | present/null | present/null | present/null |
| `recipientName` | `recipientName` | present/null | present/null | present/null |
| `isDeleted` | `isDeleted` | `false` at create | `false` at create | `false` at create |
| `deletedAt` | `deletedAt` | `null` at create | `null` at create | `null` at create |
| `settledAt` | `settledAt` (ISO8601 **string** — #1129 Gate P1: never a Firestore `Timestamp`) | present | present | present |
| `createdBy` | `createdBy` | present | present | present |
| `groupSettleUpId` | `groupSettleUpId` | omit-when-null | omit-when-null | omit-when-null |
| `correctionOfSettlementId` | `correctionOfSettlementId` | correction rows only (Admin-only marker) | same | same |

**One cell changes** (group `eventId` → absent). Model `tripId` still resolves to `groupId` for group docs via the fallback — identical value, so every downstream `tripId` consumer is bit-for-bit unaffected.

### 3.2 Code diff (complete)

1. `functions/src/callables/recordSettlement.ts:503` — delete `eventId: groupId, // sentinel — group settlements have no event`. Covers mode `'group'` (`:563`) and the gsu residual (`:579-582`) — both flow through `groupSettlementDoc`.
2. `functions/src/callables/shared/settlementCorrection.ts:217` — delete `eventId: groupId,` in `buildGroupReverseData`.
3. **No rules change** (§1.5 warning). **No client code change** (the model fallback at `settlement_model.dart:149-150` already handles the new shape).
4. Comment/doc sweep (same PR, zero behavior): `settlement_model.dart:147-148` (rewrite the fallback comment: group settlements no longer carry `eventId`; the fallback keeps legacy sentinel docs decoding — the last echo of the retired "RESEARCH.md Pitfall 3", which no longer exists in the tree); `lib/features/groups/services/group_settlement_service.dart:85` (doc-comment: "The server writes the doc with the `eventId: groupId` sentinel"); `functions/test/callables/deleteGroup.test.ts:157` seed comment cites a deleted rules line ("firestore.rules:712"); `docs/SECURITY-RULES.md` group-settlement doc-shape row; `docs/POST-LAUNCH-ROADMAP.md` #71 row (marks shipped on merge); `docs/adr/ADR-0001-settlement-names.md` #71 pointer.

---

## 4. Migration / compat strategy

**Read-path tolerance, PERMANENT. No backfill.**

- Existing prod group docs carry the sentinel; they are append-only, membership-read-gated, decoded via the tolerant model, folded by path. Valid and money-correct forever with zero action.
- New group docs (post-deploy) omit `eventId`; same decode (fallback → `tripId = groupId`), same fold.
- Mixed collections are a non-event: both shapes decode to the same `Settlement` and fold identically (no reader consults `eventId` or `scope` — §1.2/§1.3).
- Operating Contract "no real users yet → server changes deploy freely" applies, but this migration needs **no client-compat window at all**: clients cannot create settlement docs (rules deny), and every extant client reads both shapes correctly already.

---

## 5. Deploy order

**One functions-only deploy.** `firestore.rules` unchanged, indexes unchanged, client unchanged (comment-only edits ride the same PR but gate nothing).

1. Merge the PR (Gate-category paths → `/automerge` fresh review + independent refuter).
2. Run the **deploy ceremony** (`tool/pending_deploy.sh` → `tool/deploy_firebase_backend.sh` / the `deploy-ceremony` skill): `recordSettlement`, `correctSettlement`, `correctLogicalSettleUp` update in place (the changed builders live in `recordSettlement.ts` + shared `settlementCorrection.ts`); prod-state verify; advance `backend-deployed`; record in `docs/DEPLOY-LEDGER.md`.

No ordering hazard exists: there is no (rules, client, functions) combination in which any reader misbehaves, because both wire shapes decode identically everywhere (§1.2). "Rules first" reasoning (#874-style after-state rules) is inapplicable — no rules change.

---

## 6. Test plan (RED-first)

Command discipline: bare `npm test`/jest **fails fast by design** (#1157 guard in `functions/test/setup.ts`) — always `cd functions && npm run test:emulator -- <file> -t "<name>"` (per-invocation free emulator ports; safe across concurrent worktrees).

### 6.1 Callable shape tests — the RED evidence (emulator, drives `recordSettlement` + corrections)

- **`functions/test/callables/recordSettlement.group.test.ts`** — the live shape pins:
  - `'group solo happy: aggregate cap, sentinel doc shape, …'` (`:170`) asserts the exact key list **including `'eventId'`** (`:185-189`) and `eventId: GROUP // sentinel` (`:193`).
  - `'gsu happy: leg + residual + ONE activity row, …'` (`:301`) pins the residual leg's shape the same way.
  - **RED:** flip both — key list without `'eventId'`, `toMatchObject` without it, plus an explicit `expect(doc.eventId).toBeUndefined()` on the solo doc AND the residual doc. These FAIL before the `:503` deletion (field present), PASS after. Paste the failing-before output in the PR (#329 RED-evidence rule).
  - `recordSettlement.event.test.ts` must stay green **unchanged** — proves the event builder wasn't touched.
- **`functions/test/callables/shared/settlementCorrection.test.ts:290-298`** — unit-asserts `buildGroupReverseData` output with `eventId: 'g1'`. **RED:** assert no `eventId` key. Fails before the `:217` deletion.
- **`functions/test/callables/correctSettlement.test.ts:479-490`** — end-to-end asserts the written group reverse doc with `eventId: 'g'`. **RED:** same flip + `toBeUndefined()`. The `buildEventReverseData` assertions stay green unchanged.
- **Dedup invariance:** in `recordSettlement.group.test.ts` the doc id asserted via `groupScopeId(…)` (`:180`) must be **unchanged** by the migration — the existing assertion doubles as proof the ids never ingested the sentinel (§1.4). `settlementIds.test.ts` golden vectors stay green untouched.

### 6.2 Legacy-tolerance fixtures — deliberately KEEP sentinel seeds + add absent-eventId siblings

These suites **seed** group docs with the sentinel (fixture data, not shape assertions): `groupNetBalance.test.ts:107`, `balanceAggregator.test.ts:115`, `deleteGroup.test.ts:157`, `deleteGroupLockReaper.test.ts:95`, `correctLogicalSettleUp.test.ts:247`, plus the rules suites `settlementIdempotency.rules.test.ts:133` / `settlementCreateDenied.rules.test.ts:131` (which assert client create DENIAL — doc shape there is incidental). **Do not blanket-strip these seeds:** sentinel-shaped seeds are now the standing coverage that legacy prod docs keep folding/correcting/reaping correctly. Required additions:
- `groupNetBalance.test.ts`: one **mixed** case — a sentinel-shaped group settlement AND an absent-`eventId` group settlement in the same group — asserting the net equals the two-payment fold (§8, executable).
- `correctLogicalSettleUp.test.ts`: correcting a **legacy** (sentinel) original writes a **new-shape** (no `eventId`) reverse and the pair nets to zero.

### 6.3 Dart model decode (no client code change — pins the tolerance both ways)

- A group doc map **without** `eventId` decodes to `tripId == groupId`, `scope == 'group'` — passes already today (the fallback exists); add as the explicit pin against future "cleanup" of the fallback (home: `test/unit/settlement_read_fence_test.dart` or the model suite).
- Legacy shape: a doc **with** `eventId == groupId` decodes identically (same `tripId`/`scope`/`groupId`) — the permanent-tolerance pin (§4), added next to `malformed_doc_fencing_test.dart` test 7.
- `flutter analyze` clean; `flutter test` full suite.

### 6.4 Parity — must stay green UNTOUCHED

`test/unit/delete_group_balance_parity_test.dart`, `test/unit/balance_aggregate_parity_test.dart`, `functions/test/callables/groupNetBalance.test.ts`: zero oracle-source changes in this migration; green-unchanged is the parity proof.

---

## 7. Verification principles (Operating Contract) — run against the ACTUAL surfaces, reported

1. **Classify every callsite on the shared read/write path.**
   - `recordSettlement.ts` `groupSettlementDoc` (`:495-510`; write sites `:563`, `:579-582`) — **OUTBOUND**. Sentinel deleted.
   - `settlementCorrection.ts` `buildGroupReverseData:217` — **OUTBOUND**. Sentinel deleted.
   - `settlement_model.dart:149-150` `tripId` fallback — **INBOUND** (decode only; the model's `toJson` `:110-119` is the dead Supabase-era serializer, writes no Firestore doc). Kept.
   - `group_balance_provider.dart:341` — **INBOUND**, event-stream docs only; group docs folded at `:353-378` without touching `tripId`.
   - Oracle / aggregator / notifier / corrections — **INBOUND**, all path-keyed, none reads doc `eventId` (§1.2).
   - Finding: both OUTBOUND sites are edited; no INBOUND site persists anything derived from a group doc's `eventId`.
2. **Verify every concrete claim against code, not docs.** All §1 citations re-grepped this session against the post-#1129 worktree. Corrections vs v1 of this spec: `buildGroupSettlementDoc` no longer exists in lib/ (0 hits); `validGroupSettlementBase` deleted (rules `:1215-1222` = `allow create: if false`); Dart dedup helpers deleted (server port `settlementIds.ts`); the issue's `:708` rules citation is stale twice over (clause moved, then deleted with #1129).
3. **Trace one read-path per write-path.** Write: `groupSettlementDoc` (no `eventId`). Reader 1 (client): group-path stream → `Settlement.fromFirestore` → `tripId = groupId` (fallback) → group fold `group_balance_provider.dart:353-378`. Reader 2 (server): `groupRef.collection('settlements').get()` (`groupNetBalance.ts:574`) → group fold `:719-733`. Both produce byte-identical output for old and new shapes.
4. **Enumerate fields from the type.** §3.1 — all 17 `Settlement` fields + `isMarkedCorrection`, cross-checked against both live builders.
5. **Spell out data contracts.** Exact builder maps quoted (§1.1); exact fold field-sets (§1.2); exact dedup canonical string (§1.4); exact test key-lists to flip (§6.1).
6. **Verify arithmetic decomposition.** The money surfaces are the fold and the dedup id: `net = f(payerParticipantId, recipientParticipantId, amountFils, currency, path)` and `id = g(scopeKey, payer, recipient, currency, amountFils, pairEpoch)`. `eventId` is an argument to neither (grep-verified: 0 `eventId` hits in `groupNetBalance.ts`; the `settlementIds.ts:35-47` input list). Removing it changes no argument, hence no output. The gsu conservation check (`Σ legs + residual == amountFils`, `recordSettlement.ts:207-215`) and the over-outstanding cap read request ints and oracle output, not doc `eventId`.
7. **Adversarial pass on an orthogonal axis** — the change is on the schema-identity axis; §8 exercises the **money-flow × time × fallback-routing** axes.

---

## 8. Adversarial worked example (orthogonal axes: mixed legacy/new aggregate + the live mode-'group' fallback + corrections)

Post-#1129 routing note: the old #929 client-batch carve-outs (`kMaxDecomposeLegsAtomic = 9`, departed-party pre-gate) are **retired** — the server transaction bounds legs at `MAX_FAN_IN_EVENTS = 400` (`eventFanIn.ts:19`, enforced `recordSettlement.ts:194-199`) and enforces membership itself. The ONE remaining client fallback to a single aggregate group settlement is a **pure cross-event pair** (empty decomposition, `group_settle_up_screen.dart:760-763`) → mode `'group'`; an empty `legs` array on mode `'groupSettleUp'` is rejected as malformed (`recordSettlement.ts:190-193`).

Group `g` (OMR, scale 1000), members A, B:

- **T0 (pre-migration):** legacy group doc `L` = `{groupId: g, eventId: g (sentinel), scope: 'group', payer: A, recipient: B, amountFils: 3000}` — written by the pre-change `groupSettlementDoc`.
- **T1 (post-migration, decomposed):** mode `'groupSettleUp'`, legs `[e1: 1000, e2: 500]`, total 2000 → server writes 2 event legs (real `eventId` e1/e2, ids `decomposeLegSettlementId(gsuId, eN)`) + residual group doc `R` = `{groupId: g, scope: 'group', amountFils: 500}` — **no `eventId` key** — in ONE transaction.
- **T2 (post-migration, fallback):** a pure cross-event debt (no per-event attribution) routes to mode `'group'` → group doc `S` = `{groupId: g, scope: 'group', amountFils: 2000}` — **no `eventId` key**.

`groups/g/settlements` now holds `{L, R, S}` — mixed shapes.

- **Oracle:** all three load from `groupRef.collection('settlements')` (`:574`) and fold by payer/recipient/amount/currency (`:719-733`); `eventId` read on none. Group-settlement adjustment: A +5.500 paid-down / B −5.500 (3.000 + 0.500 + 2.000) — byte-identical to the pre-migration fold of the same three payments. The two event legs fold per-event exactly as before (event builder untouched). §6.2's mixed-fixture test executes this.
- **Dedup / retry:** `S`'s id = `g('group:g', A, B, OMR, 2000, pairEpoch)`; `R`'s = `decomposeResidualSettlementId(gsuId)`. Identical before/after (no eventId input); a same-observation retry derives the same id and returns `alreadyRecorded: true` — #1093 intact.
- **Aggregator:** each create fires the group-scope T2 trigger path (`balanceAggregator.ts:269`); the diff-gate keys (`:185-191`) never contained `eventId`, so trigger behavior is identical for `L` vs `R`/`S`.
- **Correction (time axis, legacy×new cross):** `correctLogicalSettleUp` on `R`'s cohort finds the residual in the **group collection** and stamps `scope: 'group'` from the path (`:123-130`); `correctSettlement` on legacy `L` resolves it by path the same way. Either reverse row is built by the post-change `buildGroupReverseData` with **no `eventId`**, and original + reverse net to zero — a legacy original corrected by a new-shape reverse is §6.2's second test.
- **Notifier:** `groupSettlementNotifier` fires on the path `groups/{gid}/settlements/{sid}` for all three; its dedupe key uses the CloudEvent id, not the doc field — no behavior change.

Every leg lands on the same invariant: **the sentinel was write-only dead weight; deleting it moves no money, changes no id, and alters no trigger/correction routing.**

---

## 9. Rollback story

- **Pre-deploy:** revert the branch; nothing shipped.
- **Post-deploy:** redeploy the previous functions revision (the `backend-deployed` tag names the prior commit; the ceremony re-run moves it back). Old builders resume writing the sentinel — which every reader still tolerates (the model fallback prefers a present `eventId`; folds ignore it). Both shapes coexist harmlessly in either direction, so rollback is non-destructive and unordered — **no rules or client rollback exists because neither changed.**
- **Data:** never touched; no data rollback. Docs written during the deployed window simply lack `eventId` — permanently valid (§4).

---

## 10. Open questions for the Gate

1. **Keep writing `scope`/`groupId`?** Spec says YES to both: `groupId` is load-bearing (the model's `tripId` fallback reads it — dropping it would break `tripId` on new group docs), and `scope` is cheap self-description on money docs even though nothing reads it today (§1.3). Removing `scope` too would be a second, unforced wire change with zero payoff — but the Gate should confirm the boundary, since "never read" cuts both ways.
2. **`tripId` model overload lingers (client-side only).** After this change the wire is clean, but `Settlement.tripId` still resolves to `groupId` for group docs. Spec treats renaming/splitting the Dart field as **out of scope** (no persistence surface; pure client refactor). Confirm.
3. **Sentinel seeds in test fixtures (§6.2).** Spec keeps them deliberately as legacy-shape coverage rather than sweeping them to the new shape. Confirm that reading ("legacy coverage") over the alternative ("stale fixture debt").
4. **Comment/doc sweep list (§3.2 item 4)** — model comment, client service doc-comment, `deleteGroup.test.ts:157` stale rules citation, `docs/SECURITY-RULES.md`, `docs/POST-LAUNCH-ROADMAP.md`, `ADR-0001`. Anything else the Gate finds joins the same PR.
