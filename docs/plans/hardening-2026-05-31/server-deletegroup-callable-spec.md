# Spec — `deleteGroup` Admin-SDK callable: server balance gate + SOFT-DELETE cascade + create-path producer fix

PR cluster: **server-deletegroup-callable**
Issue: **#190** (Tier-1 deletion cluster, findings #1–#4 of `docs/PRELAUNCH-HARDENING-AUDIT-2026-05-31.md`)
Risk surface: **functions, rules, money, schema** — **Gate required** (`/codex` fresh-context review before code).

**Concern (one):** move group deletion behind a server-authoritative callable that (a) recomputes per-actor net balance **exactly** as `BalanceCalculator` does, (b) refuses with `FAILED_PRECONDITION` on any non-zero net, (c) **soft-deletes** the group + its events (KEEPING the append-only expense/settlement money records reachable for the legal audit trail), (d) makes the soft-deleted group disappear from the home list via the `isDeleted` visibility filter, which forces a **create-path producer fix** so new groups carry `isDeleted:false`. Direct client delete is locked off in rules.

## Single-owner re-scope (read this first)

This cluster is now the **single owner** of all of:

1. the `deleteGroup` Cloud callable (`functions/src/callables/deleteGroup.ts`),
2. the server-side balance recompute (mirrors `BalanceCalculator` exactly),
3. the **soft-delete model** for group deletion (the user chose soft-delete; the prior draft's hard-`recursiveDelete` decision is **reversed**),
4. the **`isDeleted` create-path producer fix** (`createGroup` must write `isDeleted:false`; `validGroupCreate` must permit it; `userGroupsProvider` must filter `!group.isDeleted` in memory; legacy field-absent docs must stay visible with no backfill).

Soft-delete / balance content previously bled into the **rules-money** sibling spec (`rules-money-field-validation-hardening-spec.md` §6, §6.4, §6.5, §6.5.1 — its own "Gate revisions" 1 & 3 describe the `userGroupsProvider`/`Group`-model/index plumbing) and the **rate-limit** sibling spec (`server-rate-limit-counters-spec.md` §3, §3.4 — which chose the *conflicting* option (a): empty `memberIds`, no model change). **Both sibling clusters must drop their `deleteGroup`/soft-delete/balance sections; that content lives HERE now and is reconciled to ONE design (option (b): `isDeleted` filter, `memberIds` intact).** The disagreement between the two siblings (option (a) empty-memberIds vs option (b) isDeleted-filter) is resolved by the orchestrator re-scope in favour of option (b).

The sibling clusters keep ONLY their non-delete concerns:
- rules-money keeps: `validExpenseSplit`/`validSettlement` value-domain rules, settlement-deserialize crash-fence (#191–#194).
- rate-limit keeps: the join-throttle + per-UID write counters (#197/#198). The `deleteGroupAttempts/{uid}` rate-limit *counter* for the callable is defined HERE (the callable owns it), but the generic counter-infra pattern is shared with that cluster.

---

## Gate revisions R1 (2026-05-31)

Fresh-context `/codex` Gate raised three [P1]s; all three resolved here. Each was re-verified against live code before editing.

1. **SCOPE BLEED — dropped the `leaveGroup`/`removeMember` rewrite.** The prior §3.4 / HARD REQ #7 folded a server-authoritative rewrite of `leaveGroup`/`removeMember` into this cluster: a new callable + flipping `validSelfLeave`/`validCreatorRemoveMember` (`firestore.rules:241-251`) to `if false`, tearing out the LIVE client batch path (`group_provider.dart:298-340`) and LIVE UI callers (`group_members_section.dart:200`, `group_danger_section.dart:244`). None of that is the `deleteGroup` concern — it violated one-PR-one-thing and inflated the gate surface. **Removed entirely.** The removed-member group-scope debt asymmetry it cited is real (group-settlement create gates on `memberIds`, `firestore.rules:714-715`; `removeMember` strips `memberIds`, `group_provider.dart:333`) but is a **separate hardening issue** to be filed on its own. Dropping it is safe: a group with an unsettleable removed-member debt has a genuinely non-zero net, so the `deleteGroup` gate correctly returns `failed-precondition` — it refuses deletion, never corrupts state. (See §3.4, now "Scope boundary".)

2. **EQUAL-SPLIT UNIVERSE REGRESSION — §2.4 step 5 reconciled to §0.4.** §2.4 line 234 recomputed the equally/no-distribution allocation over `event.participantIds` **alone** for global/`sub_group`/`custom`-empty scopes — but the live `BalanceCalculator` splits over the FULL universe: `participants.map((p) => p.id).toSet()` (`expense_provider.dart:198,208,214`) where `participants` is `eventParticipantUids = participantIds ∪ eventLocalFormerActors` built at `group_balance_provider.dart:243-258`. Same former-actor-universe bug the spec closed for the distribution branch (HARD REQ #4) but reverted in the equal-split branch — it would under-allocate `owed` to former actors and reject a settled group (the §7-R1 "reject a settled group / delete an unsettled one" failure). **Fixed:** §2.4 step 5's equal-split recipient set now reads `participantUniverse`, reconciled verbatim to §0.4 line 83. `personal` → `{payerId}` and `custom` non-empty → `customSplitParticipants` unchanged.

3. **TEST GAP — added equal-split former-actor coverage.** The prior §8.1 case 11 and §8.4-B case 2 only exercised former actors via an explicit `splitDistribution` (the distribution branch, already correct). Per Verification principle #7 the adversarial case must exercise the broken axis. **Added** §8.1 case 11b (functions-jest: `scope:'global'`, no `splitDistribution`, former-actor in universe, settlement zeroing the equal share → must resolve; RED on a `participantIds`-only server) and §8.4-B case 4 (Dart parity: `calculateBalances` over the `{owner, gone}` universe yields `{owner:+3000, gone:−3000}`).

---

## Gate revision R2 (post-implementation, 2026-06-01)

Fresh-context `/codex review` of the as-built commit raised one [P1] against the
visibility mechanism, resolved by a design change applied with user sign-off:

- **VISIBILITY FILTER — server `where('isDeleted','==',false)` → IN-MEMORY `!isDeleted`.**
  The spec's option (b) used a server equality filter on `userGroupsProvider` +
  a new composite index + a one-time deploy backfill (§4.1, R3, R4). A Firestore
  equality query matches only docs where the field exists, so against the LIVE
  v1.3.0 install — every group predates `isDeleted` — it would hide **all**
  existing groups from Home until the backfill ran (a silent, catastrophic,
  process-dependent failure). **Resolved:** `userGroupsProvider` keeps the
  existing `memberIds + orderBy(createdAt)` query (existing index, no new one)
  and filters `!group.isDeleted` in memory. `Group.fromDoc` already defaults a
  missing `isDeleted` to `false`, so legacy groups stay visible with **no
  backfill and no composite index**; only genuinely soft-deleted groups drop.
  This supersedes: §1's `firestore.indexes.json` composite row (dropped — the
  `deleteGroupAttempts` TTL stays), §4.1's server-filter diff + the backfill
  step, §6's "after the new isDeleted == false filter" note, and §7 R3/R4.
  `createGroup` still writes `isDeleted:false` and `validGroupCreate` still gates
  it (correct producer hygiene, independent of the read path). `user_groups_visibility_test.dart`
  case 2 now pins the legacy-field-absent doc staying visible.

- **SOFT-DELETE WRITE SURFACE — two residuals confirmed + DEFERRED to #205.** The
  same review re-flagged the two risks this spec already accepted: (1) rules do
  not lock descendant creates against `isDeleted` (R7 — pre-existing app-wide
  soft-delete property; a soft-deleted event is writable today), and (2) the
  balance check is not serialized with the deletion writes (§2.5 — non-transactional
  TOCTOU, same class as `deleteAccount.ts`, actor is the owner). Both stay as
  documented residuals for the focused #190 PR and are tracked for hardening in
  **#205** (isDeleted write-locks + a quiesce/atomic-finalize two-phase). Not
  fixed here to keep #190 one-thing.

---

## 0. Verification report (run now, quoted)

Every claim was re-confirmed against code in this session (`Read`/`grep`, not from the audit doc, not from memory). Tool + file:line cited inline.

### 0.1 The four audit findings, re-verified

| Claim | Verified at | Result |
|---|---|---|
| Client `deleteGroup` does **zero** balance reads; comment admits UI-side gate | `group_provider.dart:342-371`; docstring `:344-351` ("Callers must check balance == zero before invoking (D-07 gate is UI-side)") | CONFIRMED |
| Client `deleteGroup` builds **one** `WriteBatch`, deletes member docs + inviteCode + group doc; **does NOT cascade events** | `group_provider.dart:362-370`; docstring `:349` "Does NOT cascade-delete events" | CONFIRMED |
| The UI gate is best-effort and skippable when balances haven't loaded | `group_danger_section.dart:259-273` — `final balances = balancesAsync.valueOrNull; if (balances != null) { ...hasOutstanding... }`. When `valueOrNull == null` (stream loading / errored) the whole gate is **bypassed** and delete proceeds. | CONFIRMED — the gate is unreliable even on the happy path (HARD REQ #8 fall-through) |
| Rule today: `allow delete: if isCreator();` with **no balance term** | `firestore.rules:267`; `isCreator()` at `:195-197` = `signedIn() && request.auth.uid == resource.data.createdBy` | CONFIRMED |
| Un-chunked batch → ≥499-member group permanently undeletable | `group_provider.dart:362` single `db.batch()`; Firestore hard limit 500 ops/batch | CONFIRMED |
| Removed-member debt re-injected as "former financial actor" | `group_balance_provider.dart:234` `eventFinancialUids.difference(liveMemberIds)` → `:237-240` unioned into the per-event universe | CONFIRMED |

### 0.2 Pattern-source confirmation (`deleteAccount.ts`, READ in full)

- `BatchWriter` class with auto-flush at `defaultBatchLimit = 450` (`:25,67-105`); `resolveBatchLimit()` reads `DELETE_ACCOUNT_BATCH_LIMIT` test seam (`:30-32`). We will use the **≤450-op batch chunking** for the soft-delete writes (events + group doc), NOT `recursiveDelete` (soft-delete touches docs, it does not destroy them).
- `assertNoInput` (`:107-113`) — we adapt to `assertGroupIdInput`.
- Per-UID rate limit via `runTransaction` + `expiresAt` TTL (`enforceDeletionRateLimit`, `:126-145`, against `deletionAttempts/{uid}`, limit 5 / 60 min). We mirror it against a **new** `deleteGroupAttempts/{uid}` counter.
- `onCall` options on `deleteAccount` (`:618`): `{ enforceAppCheck: false, timeoutSeconds: 540, memory: '1GiB' }`. We use `enforceAppCheck: **true**` (matches `joinGroupByInviteCode`, see §2.1).
- `getFirestore()`, `import '../admin'`, `Timestamp`, `FieldValue` available.
- Three callables registered in `functions/src/index.ts`; new export goes here.
- `deleteAccount.ts:573-574` sets group `isDeleted = true` ONLY on the no-real-survivor orphan path — this is the **other producer** of group-level `isDeleted`, and it is the read-path interaction the create-path fix must not break (traced §6.1).

### 0.3 Money decomposition — HARD REQ #2/#3 (Verification principle #6)

The server gate must reproduce the client's **per-actor `netBalance`** or it rejects "settled" groups (or — worse — deletes unsettled ones). I read the field-construction lines, not the algorithm flow.

**Decompose by reading construction lines, not the flow:**
- Per-event net (`expense_provider.dart:271`): `netBalance = (totalPaid + settlementAdj) − totalOwed`. `settlementAdj` folds event settlements `+amount` to payer, `−amount` to recipient (`:249-262`). `totalPaid` does **NOT** fold settlements — **gate on the folded `netBalance`, never on `totalPaid`.**
- Group aggregate (`group_balance_provider.dart:328`): `netBalance = eventNet + groupSettlementNet`; `groupSettlementNet` adds group-scope settlement `+amount` to payer, `−amount` to recipient (`:285-304`).
- `netBalance` **decomposes** across the slicing (per-event nets summed at `:277-281` + group settlements at `:285-304`) because it is a sum of per-UID deltas. That is the only field that decomposes; `totalPaid`/`totalOwed` are reported but are not the gate.

**HARD REQ #2 — NEVER raw-sum `amountFils`.** The client computes in `Decimal` major units, quantizing each expense's allocation to **that expense's own `currency`** subunit precision (`expense_provider.dart:152-157` falls back to `'OMR'` on an unsupported/garbage currency; `:222-224` / `_allocateWeighted:364-368` / `_allocateEqual:394-396` all quantize to `MoneySerializer.fractionDigits(currency)`). The single-currency invariant (`group.currency` immutable, audit finding #8) means today every doc in a group shares one scale, so a naive fils-sum would *happen* to agree today — but #61 (per-event-OMR settlement write) is a latent cross-currency divergence, so the server **decodes each expense/settlement by its OWN persisted `currency` field** (default `'OMR'` if absent, mirroring `expense_model.dart:161` and `settlement_model.dart:95`) via `MoneySerializer.fromSubunits(amountFils, currency) → Decimal`, sums in `Decimal`, and compares `net.abs() == 0` per actor. This matches the client's `isSettled` (`netBalance.abs() < Decimal('0.001')`, `expense_model.dart:388`) — sub-one-subunit ⇔ exactly zero in any supported scale, so the gate is `net == 0` with no tolerance band.

**HARD REQ #3 — split-VALUE decode by mode (the prior open P1).** `splitDistribution` is persisted as `int`, but the int means different things per `splitMode` (`expense_model.dart:329-339` `_splitValueToPersisted` / `:341-355` `_splitValueFromPersisted`, READ exhaustively):

| `splitMode` | persisted int | decode → `Decimal` weight |
|---|---|---|
| `exact` | `MoneySerializer.toSubunits(value, currency)` (`:335`) | `MoneySerializer.fromSubunits(persisted, currency)` (`:348`) |
| `percent` | `value × 1000` (`:336`) | `persisted / 1000` → **humanPercent in 0..100** (`:349-352`) |
| `shares` / `equally` | `value.toBigInt()` (raw int) (`:337`) | `Decimal.fromInt(persisted)` (`:353`) |

> **The prior P1:** a percent of `50.0` is stored as `50000`. Reading it as `0..100` directly (i.e. `50000`) is **1000× wrong**. The server MUST divide by `1000` for `percent`, use subunit-decode for `exact`, and raw-int for `shares`/`equally`, identically to `_splitValueFromPersisted`. (HARD REQ #3.)

### 0.4 Split UNIVERSE — HARD REQ #4 (the prior open P1 #3)

The client does NOT split over `event.participantIds` alone. `groupBalancesProvider` builds, per event (`group_balance_provider.dart:225-241`):

- `eventFinancialUids` = payer uids on this event's expenses ∪ payer/recipient uids on this event's settlements (`:225-233`). **Derived from payer/settlement uids ONLY — never from `splitDistribution` or `customSplitParticipants` keys.**
- `eventLocalFormerActors = eventFinancialUids.difference(liveMemberIds)` (`:234`), where `liveMemberIds = members.where(!m.isTombstone).map(userId)` (`:215-218`; `GroupMember.isTombstone` decoded `data['isTombstone'] ?? false`, `group_member_model.dart:40`).
- `eventParticipantUids = {...event.participantIds, ...eventLocalFormerActors}` (`:237-240`). If empty → skip event (`:241`).

`BalanceCalculator.calculateBalances` then seeds `paidMap`/`owedMap`/`settlementAdjustmentMap` **only for that universe** (`expense_provider.dart:141-146,245-247`) and **drops any key outside it** at every write (`:160` payer, `:178-182` distribution allocations, `:234` equal-split, `:250-251,256-257` settlement legs). This is the load-bearing drop mechanism: an out-of-universe `splitDistribution` key — which rules permit, since `validExpenseSplit` only checks `splitDistribution is map` (`firestore.rules:415-416`), in contrast to `payerParticipantId in participants()` (`:444`) and `customSplitParticipants.hasOnly(participants())` (`:450`) — is silently dropped, so the payer's net is only *partially* offset and the ghost never enters the balance.

**Universe by scope (HARD REQ #4), mirroring `BalanceCalculator` `:186-216`:**
- global / `sub_group`(legacy) / `custom` with **empty** `customSplitParticipants` → split set = `event.participantIds` ∪ `eventLocalFormerActors` (the universe). **This is the equal-split branch and it MUST use the full universe, NOT `participantIds` alone.** The client expresses this as `participants.map((p) => p.id).toSet()` (`expense_provider.dart:198` global, `:208` custom-empty fallback, `:214` global), and `participants` is the universe built at `group_balance_provider.dart:243-258` from `eventParticipantUids = {...event.participantIds, ...eventLocalFormerActors}` (`:237-240`). §2.4 step 5's equal-split recipient set is reconciled to this line — both say `participantUniverse`.
- `custom` with **non-empty** `customSplitParticipants` → the literal list (`:201-209`).
- `personal` → `{payerId}` (`:190-193`).
- When `splitMode != equally` && `splitDistribution` non-empty → allocate over the *distribution keys* (weighted/exact/percent), then drop keys outside the universe (`:166-184`).

> **Equal-split-universe regression guarded (Gate R1 finding #2):** the former-actor universe applies to BOTH branches — the explicit-`splitDistribution` branch AND the equal-split branch. An earlier draft fixed only the distribution branch and reverted the equal-split branch to `event.participantIds`, which would under-allocate `owed` to a former actor on a `global`/`equally` expense and reject a settled group (or, symmetrically, pass an unsettled one). §8.1 case 11b and §8.4-B case 4 exercise this exact equal-split path.

**Allocation parity (HARD REQ #4 quantize + remainder):** weighted (`shares`/`percent`) and equal allocation quantize each non-last recipient to subunit precision and let the **alphabetically-LAST recipient absorb the running remainder** so `sum(slices) == amount` exactly:
- `_allocateWeighted` (`:348-374`): recipients sorted ascending; non-last = `toCurrencyPrecision((amount × weight) / denominator)`; last = `amount − allocated`.
- equal split (`:226-241` and `_allocateEqual:385-405`): recipients sorted; `perHead = amount / count` quantized; last = `perHead + (amount − perHead×count)`.
- The remainder lands on the **last in ascending sort order** (CLAUDE.md invariant: "remainder → alphabetically-last recipient").

Fallbacks (mirror exactly): `shares` with `sum(shares) <= 0` → equal split over `distribution.keys` (`:293-298`); `exact` with `|sum − amount| > 0.001` → equal split over keys (`:318-323`); `percent` with `|sum − 100| > 0.001` → equal split over keys (`:338-343`). The tolerance is `BalanceCalculator._splitTolerance = Decimal('0.001')` (`:122`), compared in `Decimal` — the server compares in `Decimal` too (it stays in major units), so no subunit conversion of the tolerance is needed.

### 0.5 Soft-delete decision — HARD REQ #5 (reverses the prior draft)

**User chose SOFT-DELETE.** The callable:
1. Recomputes net per actor (§0.3/§0.4). Any `|net| != 0` → `FAILED_PRECONDITION`, NO writes.
2. On all-zero: set `isDeleted:true` / `deletedAt` / `updatedAt` on the **group doc** and on every non-soft-deleted **event** doc. **Do NOT touch `memberIds`.** **Do NOT hard-delete any expense/settlement** — they are the append-only legal audit trail (CLAUDE.md B3 invariant: settlements append-only; "Hard-delete user-visible records → soft-delete").
3. The group disappears from Home because `userGroupsProvider` maps `Group.fromDoc` and filters `!group.isDeleted` in memory (§4). `memberIds` is left intact so group-settlement read access (rules gate on `groupData(groupId).memberIds`, `firestore.rules:714-715`) and re-run idempotency are preserved.

**Why `isDeleted` filter (option b), not empty-`memberIds` (option a):** keeping the creator in `memberIds` preserves the rules read-grant the audit trail needs (a future support/export path, group-settlement reads). Emptying `memberIds` would silently strip read access to the very records we are preserving. The final R2 design uses a `Group`-model field + an in-memory `userGroupsProvider` filter + a create-path producer fix; it deliberately avoids a server equality filter, composite index, and backfill.

**Read-path safety of a soft-deleted-but-present group (READ the read-paths first):**
- `userGroupsProvider` (`group_provider.dart:392-405`): keep the existing `where('memberIds', arrayContains: uid).orderBy('createdAt', desc)` query, then map through `Group.fromDoc` and filter `!group.isDeleted` in memory (§4). This hides soft-deleted groups while preserving legacy docs whose `isDeleted` field is absent. Do **not** add `.where('isDeleted', isEqualTo: false)` here.
- `joinGroupByInviteCode.ts:255` already rejects joins into `isDeleted === true` groups → soft-delete is safe against invite-resurrection.
- `deleteAccount.ts:573` already writes group `isDeleted:true` on the orphan path — adding the `Group`-model `isDeleted` field + filter is consistent with that existing producer (traced §6.1).

### 0.6 Callsite classification — HARD REQ (Verification principle #1)

Shared paths: "group deletion" (write) and "group visibility / balance" (read).

| Callsite | File:line | Class | Note |
|---|---|---|---|
| `GroupService.deleteGroup` | `group_provider.dart:352` | **OUTBOUND** | Rewritten to call the callable; no direct Firestore writes remain |
| `FirebaseFunctionsService` (callable wrapper) | `firebase_functions_service.dart:5-24` | **OUTBOUND** | Add `deleteGroup(groupId)`; region-pinned `_functions` (`FirebaseConfig.functions`, `us-central1`) with a test seam already present |
| `_executeDelete` UI handler | `group_danger_section.dart:255-285` | **OUTBOUND** | Local `valueOrNull` pre-check kept as UX only; MUST always invoke the callable (incl. on the `null` fall-through) — server is the sole authority (HARD REQ #8) |
| `userGroupsProvider` | `group_provider.dart:392-405` | **BOTH** (display read + the field whose producer we fix) | keeps the existing member query; filters `!group.isDeleted` in memory; `Group.fromDoc` gains `isDeleted` read |
| `createGroup` `batch.set` | `group_provider.dart:120-129` | **OUTBOUND** (producer) | MUST write `isDeleted:false` (+ `deletedAt:null`) so new docs have explicit soft-delete state and pass `validGroupCreate` (HARD REQ #6) |
| `groupBalancesProvider` | `group_balance_provider.dart:112` | INBOUND (the read-path that defines "settled") | mirrored server-side incl. per-event universe (`:225-241`) |
| `groupEventsProvider` | `event_provider.dart:36-42` | INBOUND (feeds balance) | `where('isDeleted','==',false)` — server mirrors by skipping soft-deleted events before reading their leaves |
| Rules `allow delete` (groups) | `firestore.rules:267` | OUTBOUND (the lock) | tightened to `allow delete: if false` (the callable updates, never deletes, the group doc) |
| Rules `validGroupCreate` | `firestore.rules:199-219` | OUTBOUND (producer gate) | `hasOnly([...])` widened to permit `isDeleted` + `deletedAt` (HARD REQ #6) |

---

## 1. Files to change

| File | Change |
|---|---|
| `functions/src/callables/deleteGroup.ts` | **NEW.** The callable: validate → rate-limit → balance recompute (mirrors `BalanceCalculator`) → soft-delete group + events via `BatchWriter`. |
| `functions/src/index.ts` | Add `export { deleteGroup } from './callables/deleteGroup';` |
| `security/firestore.rules` | (1) `groups/{groupId}` `:267` `allow delete: if isCreator();` → `allow delete: if false;`. (2) `validGroupCreate.hasOnly([...])` `:201-210` add `'isDeleted'`,`'deletedAt'` + assert `isDeleted == false && deletedAt == null` on create. (3) NEW server-only `match /deleteGroupAttempts/{userId} { allow read, write: if false; }` after `:167-169`. (`validSelfLeave`/`validCreatorRemoveMember` at `:241-251` are **out of scope** — see "Scope boundary" below.) |
| `lib/features/groups/models/group_model.dart` | Add `final bool isDeleted;` (default `false`) + `final DateTime? deletedAt;` to class, constructor, `fromDoc` (`data['isDeleted'] as bool? ?? false`; `deletedAt` Timestamp→DateTime like `updatedAt`), `copyWith`, `toMap`, `fromMap` (legacy/dead SQLite path kept symmetric, defensive read). `==`/`hashCode` are id-only — adding fields is safe. |
| `lib/features/groups/providers/group_provider.dart` | (1) `createGroup` `batch.set` (`:120-129`) — add `'isDeleted': false, 'deletedAt': null`. (2) `userGroupsProvider` (`:389-405`) — keep the existing `memberIds + createdAt` query and filter `!group.isDeleted` in memory. (3) Rewrite `deleteGroup` (`:352-371`) to invoke the callable via `FirebaseFunctionsService`; map `FirebaseFunctionsException`. |
| `lib/core/services/firebase_functions_service.dart` | Add `Future<void> deleteGroup({required String groupId})` using `_functions` (region-pinned, injectable for tests). |
| `firestore.indexes.json` | Add the `deleteGroupAttempts.expiresAt` TTL field override. Do **not** add the dropped `groups` `memberIds + isDeleted + createdAt` composite; the R2 read path keeps the existing `memberIds + createdAt` query. |
| `lib/features/groups/widgets/group_danger_section.dart` | Always invoke the callable (`:255-285`); on `failed-precondition` → `groupSettleBeforeDeleting`; else → `groupFailedDelete`. The `null`-balance fall-through (`:261`) no longer skips the server call (HARD REQ #8). |
| `functions/test/callables/deleteGroup.test.ts` | **NEW.** Functions Jest suite (emulator). |
| `functions/test/firestore-rules-publish-readiness.test.ts` | Flip the two group-delete tests at `:388` and `:399` from `assertSucceeds` → `assertFails`; add member-cannot-delete + `deleteGroupAttempts` server-only + `validGroupCreate` permits `isDeleted:false` cases. |
| `test/features/groups/group_delete_callable_test.dart` | **NEW.** Client routes through the callable, performs no Firestore delete, maps errors. |
| `test/features/groups/user_groups_visibility_test.dart` | **NEW.** `userGroupsProvider` excludes `isDeleted:true`; `createGroup` writes `isDeleted:false`; legacy field-absent docs stay visible without backfill. |
| `test/unit/delete_group_balance_parity_test.dart` | **NEW.** `BalanceCalculator` parity guard on the orthogonal identity axis (out-of-universe ghost). |

L10n: reuse `groupSettleBeforeDeleting`, `groupFailedDelete`. No new keys required.

---

## 2. The callable — full contract

### 2.1 Signature & options

```ts
// functions/src/callables/deleteGroup.ts
export interface DeleteGroupInput { groupId: string; }
export interface DeleteGroupOutput {
  groupId: string;
  mode: 'softDelete';            // hard-delete is NOT a path here (HARD REQ #5)
  eventsSoftDeleted: number;
  alreadyDeleted: boolean;       // idempotent no-op when group already isDeleted/gone
}

export const deleteGroup = onCall<DeleteGroupInput, Promise<DeleteGroupOutput>>(
  { enforceAppCheck: true, timeoutSeconds: 540, memory: '1GiB' },
  async (request) => { /* ... */ },
);
```

- `enforceAppCheck: true` — matches `joinGroupByInviteCode` (`:200`); group deletion is a normal in-app action on a Play-signed build. (MEMORY `project_rd_qa_2026_05_31`: enforced-AppCheck callables need a Play-signed build; sideload fails Play Integrity. Acceptable for launch hardening. Jest wraps the handler directly and bypasses App Check.)
- `timeoutSeconds: 540, memory: '1GiB'` — same headroom as `deleteAccount` for large subtrees.

### 2.2 Validation (fail-fast, at the boundary)

1. `if (!request.auth) throw new HttpsError('unauthenticated', 'Sign-in required.');`
2. `groupId` non-empty string, no `/`:
   ```ts
   const groupId = request.data?.groupId;
   if (typeof groupId !== 'string' || groupId.length === 0 || groupId.includes('/')) {
     throw new HttpsError('invalid-argument', 'groupId must be a valid id.');
   }
   ```
3. Read `groups/{groupId}`. `if (!snap.exists) throw new HttpsError('not-found', 'Group not found.');`
4. **Idempotent no-op:** if `groupData.isDeleted === true` → return `{ groupId, mode:'softDelete', eventsSoftDeleted:0, alreadyDeleted:true }` (skip balance recompute + writes — re-deleting an already-soft-deleted group is success; mirrors `deleteAccount` `skippedGroup`).
5. **Authorize creator:**
   ```ts
   if (groupData.createdBy !== request.auth.uid) {
     throw new HttpsError('permission-denied', 'Only the group creator can delete the group.');
   }
   ```

### 2.3 Rate limit (mirror `deleteAccount`, separate counter)

`enforceDeleteGroupRateLimit(db, uid)` — verbatim shape of `enforceDeletionRateLimit` (`deleteAccount.ts:126-145`) against **`deleteGroupAttempts/{uid}`** (server-only; TTL on `expiresAt`). Limit **5 / 60 min**. Throttle **before** the balance recompute so replays are bounded. `throw new HttpsError('resource-exhausted', 'Too many delete attempts. Try again later.')`.

### 2.4 Balance-zero gate — the money core (HARD REQ #2/#3/#4)

Recompute per-actor net **in `Decimal`, decoding each doc by its own `currency`**, mirroring `group_balance_provider.dart` + `expense_provider.dart` exactly. Port `MoneySerializer` (scales table `money_serializer.dart:8-19`) + the `BalanceCalculator` allocation functions to TS.

**Reads (Admin SDK, rules-bypassing):**
```
groups/{gid}                          → currency, createdBy, isDeleted, inviteCode, memberIds
groups/{gid}/members (collection)     → userId, isTombstone           (→ liveMemberIds)
groups/{gid}/events (collection)      → participantIds, participantNames, isDeleted
.../events/{eid}/expenses             → amountFils, currency, payerParticipantId, scope,
                                         splitMode, splitDistribution, customSplitParticipants, isDeleted
.../events/{eid}/settlements          → amountFils, currency, payerParticipantId,
                                         recipientParticipantId, isDeleted
groups/{gid}/settlements (group-scope)→ amountFils, currency, payerParticipantId,
                                         recipientParticipantId, isDeleted
```

**Soft-delete predicate (mirror the client query, NOT the model default).** Client streams query `where('isDeleted','==',false)` (`event_provider.dart:42`, `expense_service.dart:36`, `settlement_service.dart:35`, `group_settlement_service.dart:35`). A Firestore equality query EXCLUDES absent/null-`isDeleted` docs. The gate counts a doc **only when `data.isDeleted === false` (strictly)** — missing/null is treated as excluded. **Do NOT use `isDeleted !== true`.** Apply to events, event-expenses, event-settlements, group-settlements. Skip a soft-deleted event wholesale *before* reading its children (event soft-delete does not cascade to its expenses on the client; `event_provider.dart:42` drops the whole event).

**`liveMemberIds`** = `{ m.userId : m.isTombstone !== true }` over `groups/{gid}/members` (mirror `:215-218`; absent/false `isTombstone` is live).

**`currencyOf(doc)`** = `MoneySerializer.isSupported(doc.currency) ? doc.currency : 'OMR'` (mirror `expense_provider.dart:155-157` and the model defaults). **`decode(amountFils, currency)`** = `MoneySerializer.fromSubunits(amountFils, currency)` → `Decimal`.

**Algorithm — per event with `isDeleted === false`** (mirror `group_balance_provider.dart:221-283` + `BalanceCalculator`):

1. `eventFinancialUids` = payer uids on non-soft-deleted expenses ∪ payer/recipient uids on non-soft-deleted settlements (`:225-233`). **From payer/settlement uids ONLY.**
2. `eventLocalFormerActors = eventFinancialUids \ liveMemberIds` (`:234`).
3. `participantUniverse = event.participantIds ∪ eventLocalFormerActors` (`:237-240`). If empty, skip (`:241`).
4. Seed `paid/owed/settlementAdj : Map<uid, Decimal>` = 0 for **every `u ∈ participantUniverse` only** (`:141-146,245-247`). No key outside the universe — the drop mechanism.
5. **For each non-soft-deleted expense:**
   - `if paid.has(payerId): paid[payerId] += decode(amountFils, currencyOf(expense))` (drop if payer ∉ universe; `:160`).
   - Build `owed` allocation (decode `splitDistribution` per `splitMode`, HARD REQ #3):
     - `splitMode` present, `!= equally`, `splitDistribution` non-empty (`:166-184`):
       - `shares` → weights = raw int per key; `sum(weights) <= 0` → equal split over keys; else weighted (alphabetically-last absorbs remainder), quantized to `currencyOf(expense)` precision (`_allocateShares`/`_allocateWeighted:283-374`).
       - `exact` → weights = `decode(value, currencyOf(expense))`; `|sum − amount| > 0.001` → equal split over keys; else use the map verbatim (`_allocateExact:308-326`).
       - `percent` → weights = `value / 1000` (**0..100, HARD REQ #3 — NOT 0..100 read raw**); `|sum − 100| > 0.001` → equal split over keys; else weighted with denominator `100`, last absorbs remainder (`_allocatePercent:328-346`).
     - Else (equally / no usable distribution) — by `scope` (`:186-216`):
       - `personal` → `{payerId}`; `custom` non-empty `customSplitParticipants` → that set; `custom` empty / `global` / `sub_group` → **`participantUniverse`** (= `event.participantIds ∪ eventLocalFormerActors`, step 3 above — NOT `event.participantIds` alone). The client reads this set as `participants.map((p) => p.id).toSet()` (`expense_provider.dart:198,208,214`), where `participants` is the universe the caller built at `group_balance_provider.dart:243-258`. **Using `event.participantIds` alone here would under-allocate `owed` to former actors and diverge from `BalanceCalculator` on the equal-split path (the equal-split-universe regression, Gate R1 finding #2 — see §0.4 note above).**
       - `perHead = amount / count` quantized to `currencyOf(expense)`; alphabetically-last absorbs `amount − perHead×count` (`:226-241`, `_allocateEqual:385-405`).
   - Add `owed` into `owed`-map dropping out-of-universe keys (`if owed.has(k): owed[k] += v`; `:178-182,232-240`). An out-of-universe `splitDistribution` key is silently dropped — exactly as the client drops it.
6. **For each non-soft-deleted event settlement** (`:249-262`): `if settlementAdj.has(payerId): settlementAdj[payerId] += decode(...)`; `if settlementAdj.has(recipientId): settlementAdj[recipientId] -= decode(...)`.
7. **Fold into global `net`** for every `u ∈ participantUniverse` (`expense_provider.dart:271` then `group_balance_provider.dart:277-281`): `net[u] += (paid[u] + settlementAdj[u]) − owed[u]`.

**Then group-scope settlements** (`group_balance_provider.dart:285-304`, NOT constrained to any universe): for each non-soft-deleted doc in `groups/{gid}/settlements`: `net[payerId] += decode(...)`; `net[recipientId] -= decode(...)`.

**Gate:**
```ts
const outstanding = [...net.entries()].filter(([, v]) => !v.isZero()); // Decimal compare
if (outstanding.length > 0) {
  throw new HttpsError('failed-precondition', 'Group has unsettled balances and cannot be deleted.');
}
```
> `net == 0` ⇔ client `isSettled` (`netBalance.abs() < 0.001`, `expense_model.dart:388`): sub-one-subunit ⇔ exactly zero. Tolerance appears only inside the `exact`/`percent` *fallback* decision, never on the gate.

### 2.5 Soft-delete writes (after the gate passes) — HARD REQ #5 + ≤450 chunking

Use `BatchWriter` (`defaultBatchLimit = 450`, reused/imported from the `deleteAccount` pattern; if extracted to `functions/src/lib/batch-writer.ts`, that extraction is in-scope here since this is the second consumer):

```ts
const now = Timestamp.now();
const writer = new BatchWriter(db);
// 1. Soft-delete every non-soft-deleted event (children stay reachable — audit trail).
for (const ev of nonDeletedEventDocs) {
  await writer.update(ev.ref, { isDeleted: true, deletedAt: now, updatedAt: now });
}
// 2. Soft-delete the group doc. memberIds untouched (preserves read grant + idempotency).
await writer.update(groupRef, { isDeleted: true, deletedAt: now, updatedAt: now });
await writer.flush();
```

- **≤450-op chunking** (the un-chunked-batch fix, audit finding `group_provider.dart:362`): a group with >449 events auto-flushes mid-cascade. Re-running on an already-`isDeleted` event/group is idempotent (a no-op update). This is deleteGroup's OWN batch path — the live single-batch client delete (`group_provider.dart:362`) caps at the 500-op Firestore limit, so a ≥499-event group would be permanently undeletable without it.
- **NO `recursiveDelete`** — expenses/settlements are append-only money records kept reachable (HARD REQ #5). The invite code stays (a stale code is rejected by `joinGroupByInviteCode.ts:255` because the group is `isDeleted`).
- Non-transactional cascade; concurrent write during the soft-delete is the documented residual (same class as `deleteAccount.ts`). Acceptable: creator destroying their own settled group.

### 2.6 Error → client mapping

| `code` | Client message |
|---|---|
| `unauthenticated` | "Please sign in and try again." |
| `invalid-argument` | "Could not delete group. Try again." |
| `not-found` | treat as success (group already gone) — UI navigates home |
| `permission-denied` | "Only the group creator can delete the group." |
| `failed-precondition` | `groupSettleBeforeDeleting` (the "settle up first" snackbar) |
| `resource-exhausted` | "Too many attempts. Try again later." |
| default | `groupFailedDelete(msg)` |

---

## 3. `security/firestore.rules` — exact changes

### 3.1 Lock group delete (`:267`)

```diff
-      allow delete: if isCreator();
+      // #190: group deletion is server-authoritative. The deleteGroup callable
+      // (Admin SDK, rules-bypassing) recomputes net balances across all events +
+      // group settlements, refuses with FAILED_PRECONDITION on any non-zero net,
+      // then SOFT-DELETES the group + its events (isDeleted:true) while keeping the
+      // append-only expense/settlement records reachable. The callable UPDATES the
+      // group doc (never deletes it), so a direct client delete must be forbidden.
+      allow delete: if false;
```

### 3.2 Permit `isDeleted`/`deletedAt` on create (HARD REQ #6 producer gate)

`validGroupCreate` (`:199-219`) — widen the `hasOnly` allow-list and assert the producer writes the false/null pair:
```diff
       function validGroupCreate() {
         return signedIn()
           && request.resource.data.keys().hasOnly([
-            'id', 'name', 'inviteCode', 'createdBy', 'memberIds', 'currency',
-            'createdAt', 'updatedAt'
+            'id', 'name', 'inviteCode', 'createdBy', 'memberIds', 'currency',
+            'createdAt', 'updatedAt', 'isDeleted', 'deletedAt'
           ])
           ...existing checks...
+          && request.resource.data.isDeleted == false
+          && request.resource.data.deletedAt == null;
       }
```
> Without widening `hasOnly`, the create-path producer fix (`createGroup` writing `isDeleted:false`) would be **rejected** by rules — every group create would fail. This is the load-bearing coupling between §3.2 and §4.

### 3.3 Server-only `deleteGroupAttempts` (after `:167-169`)

```
    // #190: per-UID deleteGroup-invocation rate-limit counters. Server-only
    // (the callable writes via the Admin SDK); clients never touch. A Firestore
    // TTL on `expiresAt` reaps them. Mirrors deletionAttempts.
    match /deleteGroupAttempts/{userId} {
      allow read, write: if false;
    }
```

### 3.4 Scope boundary — leaveGroup / removeMember are NOT in this cluster

**Gate revision R1 dropped the prior §3.4** (a server-authoritative `leaveGroup`/`removeMember` rewrite). That sub-change tore out the LIVE client batch path (`group_provider.dart:298-340`), its LIVE UI callers (`group_members_section.dart:200`, `group_danger_section.dart:244`), and two rules predicates (`validSelfLeave`/`validCreatorRemoveMember`, `firestore.rules:241-251`) — none of which is the `deleteGroup` concern. Bundling it violates one-PR-one-thing and inflated the gate surface. **It is removed; this cluster does not touch `leaveGroup`, `removeMember`, `validSelfLeave`, or `validCreatorRemoveMember`.**

**The removed-member-debt asymmetry is real but a SEPARATE finding (file as its own hardening issue):** event settlements gate creation on `data.payerParticipantId in participants()` where `participants() = eventData.participantIds`; group settlements gate on `data.payerParticipantId in groupData(groupId).memberIds` (`firestore.rules:714-715`). `removeMember`/`leaveGroup` (`group_provider.dart:313-317,332-339`) strip the uid from `memberIds` but do NOT touch any event's `participantIds`. So a removed member's **group-scope** debt becomes unsettleable (no one can `create` a group settlement naming them once they leave `memberIds`), while `group_balance_provider.dart:234` re-injects them as a former financial actor — the balance keeps showing the debt. (Event-scope debt stays settleable because `participants()` is `participantIds`, untouched by `removeMember`.)

**Why dropping it does NOT break the deleteGroup gate:** a group carrying an unsettleable removed-member group-scope debt has a genuinely non-zero net, so the `deleteGroup` gate correctly returns `FAILED_PRECONDITION` — it refuses deletion rather than corrupting state. That is the safe failure: the gate never deletes an unsettled group, and a stuck group is a pre-existing condition this cluster neither creates nor is obligated to fix. The fix for *making such a group settle-able* is the separate asymmetry issue, owned by a future cluster that touches the member-lifecycle write path.

---

## 4. Client — exact changes

### 4.1 Create-path producer fix + visibility filter (HARD REQ #6)

`group_provider.dart`:
- `createGroup` `batch.set` (`:120-129`) — add `'isDeleted': false, 'deletedAt': null`:
  ```diff
       batch.set(db.collection('groups').doc(groupId), {
         'id': groupId, 'name': name, 'inviteCode': inviteCode,
         'createdBy': uid, 'memberIds': [uid], 'currency': currency,
  +      'isDeleted': false, 'deletedAt': null,
         'createdAt': FieldValue.serverTimestamp(),
         'updatedAt': FieldValue.serverTimestamp(),
       });
  ```
- `userGroupsProvider` (`:389-405`) — keep the existing query and add the in-memory filter:
  ```diff
       return FirebaseConfig.firestore
           .collection('groups')
           .where('memberIds', arrayContains: uid)
           .orderBy('createdAt', descending: true)
           .snapshots()
  -        .map((snapshot) => snapshot.docs.map(Group.fromDoc).toList());
  +        .map((snapshot) => snapshot.docs
  +            .map(Group.fromDoc)
  +            .where((group) => !group.isDeleted)
  +            .toList());
  ```

**No backfill required after R2.** A server `== false` equality query would exclude docs with the field absent, hiding every pre-existing group until a production backfill ran. The final design avoids that failure mode: the query remains `memberIds arrayContains + orderBy(createdAt)`, `Group.fromDoc` defaults missing `isDeleted` to `false`, and the in-memory `!group.isDeleted` filter drops only genuinely soft-deleted groups. `createGroup` still writes `isDeleted:false` / `deletedAt:null` as producer hygiene and because `validGroupCreate` requires the pair.

`Group` model (`group_model.dart`): add `isDeleted`/`deletedAt` to class+ctor+`fromDoc`(`data['isDeleted'] as bool? ?? false`, `deletedAt` Timestamp→DateTime like `updatedAt:43-45`)+`copyWith`+`toMap`+`fromMap`(defensive legacy SQLite read). `==`/`hashCode` stay id-only.

### 4.2 deleteGroup via callable

`firebase_functions_service.dart` — add:
```dart
Future<void> deleteGroup({required String groupId}) async {
  await _functions.httpsCallable('deleteGroup').call({'groupId': groupId});
}
```
(`_functions` is region-pinned `FirebaseConfig.functions` (`us-central1`) with the existing `{FirebaseFunctions? functions}` test seam — no bespoke override needed, unlike the prior draft.)

`group_provider.dart` `deleteGroup` (`:352-371`) — replace the batch body with:
```dart
Future<void> deleteGroup({required String groupId}) async {
  await _ref.read(firebaseFunctionsServiceProvider).deleteGroup(groupId: groupId);
}
```
(or inject the service; mirror how the codebase already exposes `FirebaseFunctionsService`.) The method name + signature are unchanged so `group_danger_section.dart:276` keeps compiling.

### 4.3 Client gate is UX-only (HARD REQ #8)

`group_danger_section.dart:255-285`: keep the `valueOrNull` pre-check ONLY to short-circuit with the snackbar when balances are loaded AND outstanding. **When `balances == null` (the fall-through at `:261`), DO NOT skip — fall through and invoke the callable anyway.** On `FirebaseFunctionsException(code:'failed-precondition')` show `groupSettleBeforeDeleting`; on success or `not-found` → `router.go('/home')`; else `groupFailedDelete`. The server is the sole authority; the local check never decides "safe to delete."

---

## 5. Data contracts (exact keys, enumerated from the model files)

**Callable request:** `{ "groupId": string }` (no other keys).
**Callable response:** `{ groupId: string, mode: 'softDelete', eventsSoftDeleted: number, alreadyDeleted: boolean }`.

**Firestore docs read (fields from the model files, exhaustive):**
- **Expense** (`expense_model.dart:160-199` `fromFirestore`): `id, eventId, payerParticipantId, amountFils:int, currency, description, scope, subGroupId, customSplitParticipants:List<String>, splitMode, splitDistribution:Map, receiptUrl, createdAt, categoryId, note, isDeleted:bool, deletedAt, createdBy`. **Gate uses:** `amountFils, currency, payerParticipantId, scope, splitMode, splitDistribution, customSplitParticipants, isDeleted`.
- **Settlement** (`settlement_model.dart:94-124` `fromFirestore`): `id, eventId(→tripId), payerParticipantId, recipientParticipantId, amountFils:int, currency(default 'OMR'), note, settledAt, payerName, recipientName, isDeleted:bool, deletedAt, scope(default 'event'), groupId, createdBy`. **Gate uses:** `amountFils, currency, payerParticipantId, recipientParticipantId, isDeleted`. (Group settlements: `eventId == groupId` sentinel, `scope:'group'`, written by `group_settlement_service.dart:76-91`; event settlements written by `settlement_service.dart:76-91` with `currency` from the call arg, default `'OMR'`.)
- **Event** (`event_model.dart:103-158` `fromDoc`): `id, name, type, groupId, createdBy, participantIds:List<String>, participantNames:Map<String,String>, modules, startDate, endDate, isDeleted:bool, deletedAt, createdAt, updatedAt, description`. **Gate uses:** `isDeleted` (skip whole event if `!== false`), `participantIds` (per-event universe), `participantNames` (display fallback only).
- **GroupMember** (`group_member_model.dart:31-43` `fromDoc`): `id, userId:String, displayName, role, isShadow:bool(?? false), isTombstone:bool(?? false), joinedAt`. **Gate uses:** `userId, isTombstone` → `liveMemberIds = { userId : isTombstone !== true }`.
- **Group** (`group_model.dart:33-47` `fromDoc`, **+ the new fields**): `id, name, inviteCode, createdBy, memberIds:List<String>, currency, createdAt, updatedAt` **+ `isDeleted:bool(?? false)`, `deletedAt:DateTime?`**. **Callable uses:** `createdBy` (authorize), `currency` (subunit scale fallback), `isDeleted` (idempotent no-op). **Write:** `isDeleted:true, deletedAt, updatedAt` (NOT `memberIds`).

**`splitDistribution` decode contract (HARD REQ #3, the load-bearing detail a fresh decode gets wrong):** persisted ints differ by `splitMode` (`expense_model.dart:329-355`): `exact` → subunits (`fromSubunits`); `percent` → `value×1000` (decode `/1000` → 0..100); `shares`/`equally` → raw count. The TS port MUST switch on `splitMode` identically.

**Rule predicate text changed:** `allow delete: if false;` (`:267`); `validGroupCreate` `hasOnly([... 'isDeleted','deletedAt'])` + `isDeleted == false && deletedAt == null` (`:201-219`); new `match /deleteGroupAttempts/{userId} { allow read, write: if false; }`.

---

## 6. Read-paths per write-path (principle #3)

| Field/doc written | Who reads it after | Effect |
|---|---|---|
| `groups/{gid}.isDeleted = true` | `userGroupsProvider` (`group_provider.dart:389-405`, after the in-memory `!group.isDeleted` filter) | group vanishes from Home/journey lists; `memberIds` intact so group-settlement reads still authorized. |
| `groups/{gid}.isDeleted = true` | `groupDetailProvider` (`:428`) | resolves the group with `isDeleted:true`; the danger section already navigates `/home` on success, so the creator leaves the detail page. (Non-blocking: a stale deep-link to the detail would render a soft-deleted group; out of scope — same as today's soft-deleted-event behaviour.) |
| `groups/{gid}.isDeleted = true` | `joinGroupByInviteCode.ts:255` | future join with the stale invite code → `not-found`. Correct. |
| `groups/{gid}/events/*.isDeleted = true` | `groupEventsProvider` (`event_provider.dart:42`), `groupBalancesProvider` (`group_balance_provider.dart:112`) | events drop from the list and from the balance pass; child expenses/settlements stay reachable as the audit trail. |
| `groups/{gid}.isDeleted:false` (createGroup) | `validGroupCreate`; `userGroupsProvider` model/default path | new groups carry explicit soft-delete state (HARD REQ #6); legacy field-absent groups remain visible because `Group.fromDoc` defaults false. |
| `deleteAccount.ts:573` group `isDeleted:true` (orphan path) | `userGroupsProvider` in-memory filter (newly added) | **interaction (§6.1):** an orphan group `deleteAccount` soft-deletes now ALSO drops from the surviving member's list. Verified safe — `deleteAccount` empties the deleting uid from `memberIds` (`:565`) so the group already vanished for them; for any *other* still-present member, the orphan path only runs when there is **no real survivor** (`:571`), so no live member is wrongly hidden. |

### 6.1 `deleteAccount` interaction (traced)

`deleteAccount.ts:571-575` sets group `isDeleted:true` + `createdBy:'deleted-user'` ONLY when `!hasRealSurvivor` (the deleting user was the last real member). Adding the `userGroupsProvider` in-memory `!group.isDeleted` filter therefore hides exactly those no-survivor orphans — which is correct (no one is left to use them). Groups with a real survivor are NOT soft-deleted by `deleteAccount` (it only swaps the uid→tombstone in `memberIds`), so survivors keep seeing them. No regression. (This is why HARD REQ #6's filter is consistent with the existing `isDeleted` producer.)

---

## 7. Risks & out-of-scope

- **R1 — Gate divergence from client `BalanceCalculator`.** A mis-ported split mode, the percent `/1000` decode (HARD REQ #3), the per-doc currency decode (HARD REQ #2), the per-event universe (HARD REQ #4), or the strict-`=== false` predicate would reject a settled group or delete an unsettled one. *Mitigation:* port mode-by-mode from `expense_provider.dart` + `group_balance_provider.dart`; the universe + strict predicate + percent-decode + per-doc-currency are mandated verbatim in §0.3/§0.4/§2.4; table-driven tests (§8.1) cover every scope×splitMode plus the regression cases; §8.4 cross-impl parity guard on the identity axis.
- **R2 — Rules tests assert OLD behavior.** `:388`/`:399` (`assertSucceeds` on creator client-delete) break; flip both to `assertFails` (§8.2) or CI goes red.
- **R3 — Do not reintroduce the server equality filter.** The R2 design deliberately keeps the existing `memberIds(CONTAINS)+createdAt(DESC)` query and filters in memory. Re-adding `where('isDeleted','==',false)` would require a composite index and would hide legacy field-absent groups until a backfill ran.
- **R4 — Backfill not required under R2.** Legacy groups with no `isDeleted` field stay visible because `Group.fromDoc` defaults missing `isDeleted` to `false` before the in-memory filter runs.
- **R5 — `deleteGroupAttempts` TTL** not auto-created by the rules block; register the TTL field in `firestore.indexes.json` `fieldOverrides` (mirror `deletionAttempts:38-46`) at deploy (fast-follow acceptable per MEMORY `project_firestore_ttl_state`). Counter still bounds replays without the TTL; TTL only reaps.
- **R6 — App Check enforced** → emulator/sideload calls fail attestation; production needs a Play-signed build (MEMORY `project_rd_qa_2026_05_31`). Jest wraps the handler directly (bypasses App Check) — unaffected.
- **R7 — Soft-deleted group still resolves via `groupDetailProvider`/deep link** (§6 row 2). Same residual as today's soft-deleted events; out of scope.
- **OUT OF SCOPE:** the #61 per-event-OMR settlement write (latent cross-currency divergence — the non-OMR test is "latent until #61", §8.1 case 9); receipt/Storage deletion (dead feature); any change to the rules-money value-domain rules or the rate-limit join/write counters (those stay in their clusters).

---

## 8. TEST PLAN (failing-first; RED → GREEN)

### 8.1 `functions-jest` — callable behavior (emulator)

- **testFile:** `functions/test/callables/deleteGroup.test.ts`
- **Harness:** `firebase-functions-test` `wrap(deleteGroup)`, Admin SDK vs the Firestore emulator (mirror `deleteAccount.test.ts` seed helpers).
- **runCommand:** `cd functions && npm run test:emulator -- deleteGroup.test.ts`

| # | Case | Currently-failing assertion |
|---|---|---|
| 1 | missing auth | `await expect(wrapped({data:{groupId:'g'}})).rejects.toMatchObject({code:'unauthenticated'})` — *fails now: module not found* |
| 2 | non-creator | group `createdBy:'owner'`, caller `member` → `rejects … {code:'permission-denied'}` |
| 3 | missing group | `groupId:'ghost'` → `rejects … {code:'not-found'}` |
| 4 | invalid groupId | `''` and `'a/b'` → `rejects … {code:'invalid-argument'}` |
| 5 | **clean soft-delete** (zero balance, no events) | resolves; `getDoc(groups/g).data().isDeleted === true`; `deletedAt` set; `memberIds` UNCHANGED; `mode:'softDelete'` |
| 6 | **outstanding balance rejected (exact split)** | event expense `amountFils:12000` paid by owner, `splitMode:'exact'`, `splitDistribution:{owner:6000, member:6000}`, no settlement → `rejects … {code:'failed-precondition'}`; group `isDeleted` still falsey (no partial write) |
| 7 | **settled via settlement → allowed** | same expense + event settlement `member→owner amountFils:6000` → resolves; group `isDeleted:true` |
| 8 | **group-scope settlement counted** | outstanding event net offset by `groups/g/settlements` (`scope:'group'`, `eventId==groupId`) → resolves. Exercises the `:285-304` fold |
| 9 | **non-OMR group (latent until #61)** | event expense `currency:'USD' amountFils:1000` ($10.00) split exact `{owner:500, member:500}` + settlement zeroing → resolves. Proves per-doc `currency` decode (HARD REQ #2): a raw fils-sum would still be 0 here, so ALSO assert the percent variant: expense `currency:'USD' amountFils:1000 splitMode:'percent' splitDistribution:{owner:50000, member:50000}` (50% each = 50000 persisted) → the `/1000` decode gives 50+50=100; a 0..100-raw read (50000+50000) would hit the `|sum−100|>0.001` fallback to equal-split (still 500/500 here) — so to make the percent-decode bug *observable*, use `{owner:60000, member:40000}` (60/40) and a settlement that zeroes the 60/40 split; a raw-read server falls back to 50/50 and the settlement no longer zeroes → it would wrongly `failed-precondition`. Assert resolves. (HARD REQ #3 percent decode) |
| 10 | **percent split happy path** | expense `splitMode:'percent' splitDistribution:{owner:70000, member:30000}` (70/30) paid by owner + settlement zeroing the 70/30 net → resolves. A 0..100-raw read computes a different owed and the settlement won't zero it → `failed-precondition`. (HARD REQ #3) |
| 11 | **former-actor-in-universe (distribution branch)** | event `participantIds:['owner']`; an expense paid by `owner` split `{owner, gone}` where `gone` is a member with `isTombstone:true` (so `gone ∉ liveMemberIds`) and `gone` is a payer/recipient on a settlement → `gone` re-injected into the universe (`:234`); seed a settlement zeroing `gone`'s net → resolves. Without former-actor injection the server would compute a different `owner`/`gone` net. (HARD REQ #4) |
| 11b | **former-actor-in-universe (EQUAL-SPLIT branch — Gate R1 finding #2)** | event `participantIds:['owner']`; member `gone` with `isTombstone:true` (so `gone ∉ liveMemberIds`) who is a **payer or settlement actor** in the event (re-injected into the universe via `:234`); a `scope:'global'` expense with **NO `splitDistribution`** (or `splitMode:'equally'`) `amountFils:6000` paid by `owner` → equal split over the universe `{owner, gone}` = 3000 each → `owner` net `6000−3000=+3000`, `gone` net `0−3000=−3000`. Seed an event/group settlement `gone→owner amountFils:3000` zeroing it → **resolves**. *Fails on a server that splits the equal/global branch over `event.participantIds`=`['owner']` alone: it would owe `owner` the full 6000, the settlement no longer zeroes, → `failed-precondition`.* This is the precise path §2.4 step 5 gets wrong if it uses `event.participantIds` instead of `participantUniverse`. (HARD REQ #4, R2) |
| 12 | **out-of-universe `splitDistribution` ghost → must REJECT (dangerous direction)** | live event `participantIds:['owner','member']`, no settlements. Expense `amountFils:6000` paid by `owner`, `splitMode:'shares' splitDistribution:{owner:1,member:1,ghost:1}` (`ghost` ∉ participantIds, not a payer/settlement actor). **Correct (per-event-drop):** weighted over sorted keys `ghost,member,owner` = 2000 each, but `owed` seeded only for `{owner,member}` → ghost's 2000 dropped → owner net `6000−2000=+4000`, member `0−2000=−2000` → NON-ZERO → `rejects … {code:'failed-precondition'}`; group NOT soft-deleted. A "single global map" server would credit ghost −2000 and net to 0, wrongly deleting. (HARD REQ #4 / prior P1) |
| 13 | **soft-deleted event holding a LIVE unsettled expense → resolves** | event `isDeleted:true` with a non-soft-deleted child expense `amountFils:9000` split `{owner,member}`, no settlement (would be non-zero if counted). Group has no other docs → resolves (server skips the soft-deleted event, mirroring `event_provider.dart:42`); assert the child expense doc is STILL present (soft-delete keeps the audit trail — NOT hard-deleted). *Fails on a server that filters `isDeleted` only on leaves: it would `failed-precondition`.* |
| 14 | **`isDeleted`-ABSENT doc treated as deleted-for-balance** | live event; an expense written with NO `isDeleted` field whose split would be non-zero, no offsetting settlement. Client `where('isDeleted','==',false)` excludes it → group shows settled → callable resolves (strict `=== false`). *Fails on `isDeleted !== true`.* |
| 15 | rate limit | invoke 6× (or seed counter to 5) → 6th `rejects … {code:'resource-exhausted'}` |
| 16 | idempotent retry | call twice on a settled group; 2nd → `alreadyDeleted:true` resolves no-op; group stays `isDeleted:true` |
| 17 | **large group chunking** | event with 600 settled expenses + 460 events all settled → resolves; all events `isDeleted:true`; no batch-limit throw. Set `DELETE_ACCOUNT_BATCH_LIMIT=50` (or the deleteGroup equivalent seam) to force mid-cascade auto-flush. Proves the `BatchWriter` ≤450 chunking (the un-chunked-batch fix; `group_provider.dart:362` single batch caps at 500) |

### 8.2 `rules-emulator` — lock the client path + producer gate

- **testFile:** `functions/test/firestore-rules-publish-readiness.test.ts` (edit existing)
- **runCommand:** `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts`

| # | Case |
|---|---|
| 1 | `:388` flip `assertSucceeds(batch.commit())` → `assertFails(...)` (creator can no longer client-delete the group doc). Rename to "creator cannot client-delete group (server-only)". |
| 2 | `:399` same flip to `assertFails` (legacy-missing-invite path). |
| 3 | (new) member also cannot delete group doc — `assertFails(member.doc('groups/g1').delete())`. |
| 4 | (new) `deleteGroupAttempts` server-only — `assertFails(owner.doc('deleteGroupAttempts/owner').get())` and `.set(...)`. |
| 5 | (new) `validGroupCreate` permits `isDeleted:false`/`deletedAt:null` — `assertSucceeds(owner.doc('groups/g-new').set({...valid..., isDeleted:false, deletedAt:null}))`; and `assertFails` when `isDeleted:true` on create (producer must write `false`). |

### 8.3 `dart-widget` — client routes through callable, maps errors, fall-through

- **testFile:** `test/features/groups/group_delete_callable_test.dart` (new)
- **runCommand:** `flutter test test/features/groups/group_delete_callable_test.dart`

| # | Case |
|---|---|
| 1 | `deleteGroup` invokes the injected `FirebaseFunctionsService.deleteGroup`, performs NO Firestore delete — inject a fake `FirebaseFunctionsService`; assert the callable was called with `'g'` AND the fake group doc is untouched. *Fails now: `deleteGroup` does a client batch delete.* |
| 2 | `failed-precondition` → `groupSettleBeforeDeleting` snackbar. (Pump the danger section via `pumpRihlaApp`; override `sharedPreferencesProvider`; no `pumpAndSettle` after the helper per MEMORY `feedback_pump_rihla_app_contracts`.) |
| 3 | generic `code:'internal'` → `groupFailedDelete`. |
| 4 | **null-balance fall-through (HARD REQ #8)** — `groupBalancesProvider` still loading (`valueOrNull == null`); tap delete → assert the callable IS invoked anyway (server is the authority). *Fails on a client that skips the call when balances are null.* |

### 8.4 `dart-unit` — visibility producer + parity guard (orthogonal identity axis)

- **testFile A:** `test/features/groups/user_groups_visibility_test.dart` (new) — `runCommand: flutter test test/features/groups/user_groups_visibility_test.dart`
  1. `createGroup` writes `isDeleted:false` + `deletedAt:null` into the group doc (read the FakeFirebaseFirestore doc; assert the keys). *Fails now: createGroup omits them.*
  2. `userGroupsProvider` excludes a group with `isDeleted:true`, includes `isDeleted:false`. (FakeFirebaseFirestore.)
- **testFile B:** `test/unit/delete_group_balance_parity_test.dart` (new) — `runCommand: flutter test test/unit/delete_group_balance_parity_test.dart`
  1. `BalanceCalculator.calculateBalances` returns all-zero net for the §8.1 case 7/8 fixtures, so Dart client and TS server agree on "settled" for the same docs.
  2. **(adversarial — out-of-universe ghost, HARD REQ #4)** reproduce §8.1 case 12 on the Dart side: `calculateBalances(participants:[owner,member], expenses:[shares-split {owner:1,member:1,ghost:1}, amount 6000], settlements:[])`. Assert the per-UID net is `{owner:+4000, member:−2000}` with NO `ghost` entry — the out-of-universe ghost share (2000) is dropped, NOT redistributed. This is the exact net the corrected server must produce; a "single global map" server yields `{owner:+4000,member:−2000,ghost:−2000}` (sum 0). Exercises the identity axis (principle #7). *Fails if the client's `owedMap.containsKey` drop guard changes, or — vs the server fixture — if the server uses the shortcut.*
  3. **(adversarial — percent decode, HARD REQ #3)** `calculateBalances` for a 60/40 percent expense matches the server's `/1000` decode (60.0/40.0), NOT the 0..100-raw fallback (50/50). Pins the §8.1 case 9/10 contract on the money axis.
  4. **(adversarial — equal-split former-actor universe, HARD REQ #4 / Gate R1 finding #2)** the orthogonal axis to case 2: case 2 exercised the *distribution* branch (explicit `splitDistribution` keys); this exercises the *equal-split* branch the §2.4 line-234 bug touches. Build `participants:[owner, gone]` (the universe, with `gone` a former actor re-injected — mirror how `group_balance_provider.dart:243-258` constructs `eventParticipants` from `eventParticipantUids`), `expenses:[ scope:global, splitMode:null/equally, NO splitDistribution, amount:6000, payer:owner ]`, `settlements:[]`. Assert per-UID net is `{owner:+3000, gone:−3000}` — `gone` receives an equal share because it is in the universe. This is the exact net the corrected server (using `participantUniverse`, not `event.participantIds`) must produce; a server splitting over `participantIds=['owner']` alone yields `{owner:+6000}` with no `gone` entry → divergent. *Fails RED against the original §2.4 line-234 wording (`event.participantIds`).*

---

## 9. Definition of done

- [ ] `/codex` fresh-context Gate run on this spec; no [P1]s before code.
- [ ] Failing tests written first (§8.1 case 1, §8.3 case 1, §8.4-A case 1) — RED — then implement — GREEN.
- [ ] `cd functions && npm run build` clean; `npm run test:emulator` green.
- [ ] `flutter analyze` clean; `flutter test test/features/groups/ test/unit/` green.
- [ ] Rules tests `:388/:399` flipped + new producer/lock cases (§8.2) — no stale `assertSucceeds`.
- [ ] `deleteGroupAttempts.expiresAt` TTL registered in `firestore.indexes.json`; no groups `memberIds + isDeleted + createdAt` composite and no `isDeleted` backfill required under R2 (§4.1).
- [ ] One concern: deleteGroup (server-authoritative balance gate + soft-delete cascade + ≤450 chunking + `isDeleted` create-path producer). **NOT in scope:** `leaveGroup`/`removeMember`/`validSelfLeave`/`validCreatorRemoveMember` (the removed-member-debt asymmetry is its own separate hardening issue — §3.4). No rules-money value-domain changes, no rate-limit join/write counters, no opportunistic cleanup.
- [ ] Conventional commit `feat(functions): server deleteGroup callable with balance gate + soft-delete cascade (#190)`.
