# #752 — Decompose group-level settlements into per-event writes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. This plan is **Gate-category** (money math + write path + firestore.rules + schema field). Do NOT implement until the fresh-context Opus Gate verdict has zero [P1]s.

**Goal:** A group-level settle-up P→R for amount A in currency C must reduce the *per-event* ledger balances (not just the group/home aggregate), by **persisting** the per-event truth as real settlement docs, while keeping the group/home balance byte-identical and the server oracle untouched.

**Architecture:** When recording a group transfer, a single **pure allocator** (the SSOT for both the displayed breakdown and the write) decomposes A — in integer subunits — into N per-event attributions + one cross-event residual that sum to A exactly. The N attributions are written as **event settlements** (`groups/{gid}/events/{eid}/settlements`, which event ledgers already read and the oracle already folds per-event); the residual is written as one **group settlement** (`groups/{gid}/settlements`, scope:'group', which the oracle already folds globally). All docs of one settle-up share a new `groupSettleUpId` so the group-level history can surface them (PR1) and a fast-follow can regroup + atomically correct them (PR2). A minimal, additive `firestore.rules` change relaxes event-settlement-create authz (so settle-on-behalf by a non-event-participant member is accepted) and allow-lists the new field. **The server oracle (`groupNetBalance.ts`) is NOT touched** — it already folds event settlements per-event and group settlements globally, so the decomposition is byte-for-byte equivalent at the aggregate.

**Scope (split per Gate round 3, owner-approved 2026-06-29):** PR1 (this plan) = the verified-clean money/rules/decompose core + display + history union, hiding the one-tap correct affordance on decomposed settle-ups so nothing half-corrects. PR2 (fast-follow, own Gate) = corrections-of-decomposed via an atomic `WriteBatch` (§6).

**Tech Stack:** Flutter / Riverpod 2.x (no codegen), `decimal` package, Firestore, `MoneySerializer` (integer subunits at the boundary), Cloud Functions TS oracle (read-only reference here), Jest + Firestore emulator (rules tests), `flutter_test` + `fake_cloud_firestore`.

---

## 0. Verified context (code, not docs — re-confirm before each task)

The bug, the parity mechanism, and every claim below were verified against live code on 2026-06-28/29 in this worktree. Branch note: **implement from a fresh branch off `main`**, not off `feat/485-split-card` (the current worktree HEAD; #485/PR #751 is unmerged and unrelated). The settlement files are unchanged from main on that branch, but re-verify.

### 0.1 The bug (confirmed)
- Event ledger surfaces read **only** event settlements: `ledger_view_provider.dart:66-68`, `settle_up_screen.dart`, `event_command_center.dart`.
- Group settlements fold into the **aggregate only**: `group_balance_provider.dart:413-421` (`netBalance: eventNet + groupSettlementNet`) and are excluded from `perEventBreakdown` (`group_balance_provider.dart:429-433, 464-515`, `participantIds`-only by design).
- Server mirrors this: group settlements fold globally (`groupNetBalance.ts:705`), event settlements per-event (`foldEventNet`, `groupNetBalance.ts:432`).
- Current write site: `group_settle_up_screen.dart:577-589` writes ONE `addGroupSettlement` (the `.read(...)` chain starts at `:577`).

### 0.2 Parity mechanism that makes decompose safe (confirmed)
- Oracle separates event vs group settlements by **collection path, not the `scope` field** (`loadGroupBalanceSnapshot`, `groupNetBalance.ts:549,560`). So real event-subcollection docs fold per-event; the residual group doc folds globally.
- Both writes trigger a full server recompute of `groups/{gid}/aggregates/balance`: `eventModuleBalanceAggregator` (`balanceAggregator.ts:254`, module ∈ {expenses,settlements}) and `groupSettlementBalanceAggregator` (`balanceAggregator.ts:268`). Recompute is full + idempotent + staleness-guarded by `sourceTimeMs` — fan-out order is irrelevant.
- For event settlements, the per-event fold is **universe-gated** (`groupNetBalance.ts:438,441`; client `expense_provider.dart:332,337`). Payer & recipient are participants of every attributed event **by construction** (attribution only targets events where their `participantIds`-only per-event net is non-zero), so nothing drops. Result: writing N event settlements (Σ a_e) + 1 group residual (r) where Σa_e + r = A produces **payer += A, recipient −= A** at the aggregate — identical to one group settlement of A. **No oracle change needed.**

### 0.3 The three problems with the naive issue spec (this plan fixes all three)
1. **Negative residual.** `Σ min(|fromNet_e|, toNet_e)` can exceed A (offsetting cross-event nets that cancel at aggregate; e.g. payer −10/E1 +4/E2, recipient +10/E1 −4/E2 → A=6 but naive Σ=10 → residual −4) and partial edits make it worse. Fixed by the **capped subunit allocator** (§1).
2. **Authz wall.** `validEventSettlementCreate` requires `isEventParticipant(writer)` (`firestore.rules:770`). OK for self-settle (writer=payer) and creditor-records (writer=recipient), but **rejects** settle-on-behalf (#595) and corrections (#283) by a non-event-participant. Fixed by the **rules relaxation** (§3).
3. **Group history + corrections regression.** Group settle-up history reads only group docs (`group_settle_up_screen.dart:95-97,151`); decompose with residual 0 (the common single-event case) leaves NO group doc → the payment vanishes from group history and has no row to correct. Fixed by the **`groupSettleUpId` link + history regroup + corrections-by-id** (§5/§6).

---

## 1. KEYSTONE — the pure allocator (`BalanceCalculator.decomposeGroupSettlement`)

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart` (add static method to `BalanceCalculator`, near `calculateOptimalSettlements`/`_toCurrencyPrecision`)
- Test: `test/unit/decompose_group_settlement_test.dart` (new)

**Contract (exact):**

```dart
/// Pure decomposition of a group transfer [amount] (payer→recipient, in
/// [currency]) into per-event attributions + a cross-event [residual] — the
/// SINGLE source of truth for BOTH the displayed breakdown and the written
/// settlements (#752, #242 WYSIWYG). Computed in integer subunits so
/// Σ(perEvent) + residual == toSubunits(amount) EXACTLY (whole-subunit,
/// MoneySerializer-quantized).
///
/// Invariants (pinned by tests):
///  - residual >= 0 ALWAYS (never a negative/reverse settlement).
///  - perEvent[e] <= min(|payerNet_e|, recipientNet_e) (never more than the
///    event "earned") AND Σ perEvent <= toSubunits(amount).
///  - Σ perEvent + residual == toSubunits(amount), exactly.
///  - Deterministic given [eventOrder]; events absent from a party's breakdown
///    contribute zero (skipped).
///  - amount <= 0 → ({}, 0).
///
/// Cross-event debt (payer owes in E1, is owed in E2) and partial settlements
/// (amount < full suggested) both fall into [residual] by construction.
static ({Map<String, Decimal> perEvent, Decimal residual})
    decomposeGroupSettlement({
  required Map<String, Map<String, Decimal>> payerPerEventNet,     // perEventBreakdown[payerId]: eventId -> currency -> net
  required Map<String, Map<String, Decimal>> recipientPerEventNet, // perEventBreakdown[recipientId]
  required String currency,
  required Decimal amount,
  required List<String> eventOrder, // deterministic event order (group events list order)
});
```

**Implementation:**

```dart
static ({Map<String, Decimal> perEvent, Decimal residual})
    decomposeGroupSettlement({
  required Map<String, Map<String, Decimal>> payerPerEventNet,
  required Map<String, Map<String, Decimal>> recipientPerEventNet,
  required String currency,
  required Decimal amount,
  required List<String> eventOrder,
}) {
  final cur = MoneySerializer.isSupported(currency) ? currency : 'OMR';
  final perEvent = <String, Decimal>{};
  var remaining = MoneySerializer.toSubunits(amount, cur);
  if (remaining <= 0) return (perEvent: perEvent, residual: Decimal.zero);

  for (final eventId in eventOrder) {
    if (remaining <= 0) break;
    final payerNet =
        MoneySerializer.toSubunits(payerPerEventNet[eventId]?[cur] ?? Decimal.zero, cur);
    final recipientNet =
        MoneySerializer.toSubunits(recipientPerEventNet[eventId]?[cur] ?? Decimal.zero, cur);
    if (payerNet < 0 && recipientNet > 0) {
      final cap = (-payerNet) < recipientNet ? (-payerNet) : recipientNet;
      final take = cap < remaining ? cap : remaining;
      if (take > 0) {
        perEvent[eventId] = MoneySerializer.fromSubunits(take, cur);
        remaining -= take;
      }
    }
  }
  return (perEvent: perEvent, residual: MoneySerializer.fromSubunits(remaining, cur));
}
```

**Why subunits, not Decimals:** per-event nets are already whole-subunit (#596 invariant); working in `int` subunits makes Σ exact and the round-trip `fromSubunits(take, cur)` lossless (`take` is a whole subunit). This mirrors `_allocateEqual`'s quantize discipline (`expense_provider.dart:806`).

**Casing contract [Gate R4 P3]:** `currency` MUST be the SAME bucket key used in `payerPerEventNet`/`recipientPerEventNet` (both derive from the one balance computation, which fences with `MoneySerializer.isSupported(c) ? c : 'OMR'` — case preserved). The map lookups use `cur` verbatim, so do NOT `.toUpperCase()` it — that would risk a mismatch against a case-preserved bucket key. Callers pass the bucket key from `balancesData.balances.keys` (the tile's `currency`), so case is consistent by construction. The internal `isSupported(currency) ? currency : 'OMR'` fence is only to keep the `MoneySerializer` calls from throwing on an unsupported code (they uppercase internally).

**Tests (write FIRST, RED):** table-driven (money code → CLAUDE.md mandates clean/warning/error cases):
1. Single event, full amount: payer −10/E1, recipient +10/E1, A=10 → `{E1:10}`, residual 0.
2. **Negative-residual guard:** payer −10/E1 +4/E2, recipient +10/E1 −4/E2, A=6 → `{E1:6}`, residual 0. (Naive formula would give residual −4.)
3. Cross-event residual: payer −5/E1, recipient +5/E2 (no shared event) → `{}`, residual 5.
4. Partial edit: case 1 with A=4 → `{E1:4}`, residual 0 (capped below the earned 10).
5. Multi-event split with cap exhaustion order: payer −3/E1 −5/E2, recipient +10/E1 +10/E2, A=6, order [E1,E2] → `{E1:3, E2:3}`, residual 0.
6. Multi-currency isolation: nets present in OMR and USD; decompose for USD only touches USD (per-bucket).
7. Conservation property test: for assorted inputs assert `Σ toSubunits(perEvent) + toSubunits(residual) == toSubunits(amount)` and `residual >= 0`.
8. JPY (scale 1) and a terminating sub-subunit case to prove whole-subunit output.

---

## 2. Schema — `groupSettleUpId` on `Settlement`

**Files:**
- Modify: `lib/features/ledger/models/settlement_model.dart` (field + `fromFirestore`)
- Modify: `lib/features/ledger/services/settlement_service.dart` (`addSettlement` optional param → `data['groupSettleUpId']`)
- Modify: `lib/features/groups/services/group_settlement_service.dart` (`addGroupSettlement` optional param)
- Test: `test/unit/settlement_service_test.dart`, `test/unit/group_settlement_service_test.dart`

**Field:** `final String? groupSettleUpId;` (nullable; null on legacy docs and on directly-recorded event settlements). Read in `fromFirestore` as `data['groupSettleUpId'] as String?`. Write only when non-null (omit the key otherwise, so directly-recorded settlements keep the existing shape and legacy docs stay valid).

> Enumerated from the type (verification principle 4): `Settlement` fields are id, tripId, payerParticipantId, recipientParticipantId, amount, note, settledAt, payerName, recipientName, isDeleted, deletedAt, scope, groupId, createdBy, currency (+ new groupSettleUpId). `toFirestore` is not a method on this model — writes are assembled in the two services; both must add the key.

---

## 3. Rules — additive relaxation + field allow-list (Gate-category; deploy rules only)

**Files:**
- Modify: `security/firestore.rules`
- Test: `functions/test/.../firestore-rules-*.test.ts` (emulator)

**3a. Allow-list the new field** in BOTH settlement validators:
- `validEventSettlementBase` `hasOnly([...])` (`firestore.rules:739-753`): add `'groupSettleUpId'`.
- `validGroupSettlementBase` `hasOnly([...])` (`firestore.rules:927-943`): add `'groupSettleUpId'`.
- In `validSettlementCore` (`:110`) add: `&& (!('groupSettleUpId' in data) || data.groupSettleUpId is string)`.
  - **[Gate R1 P1 — load-bearing]** Use the `!('x' in data) ||` guard, NOT a direct `data.groupSettleUpId == null` access. `validSettlementCore` runs on EVERY settlement create (`:765` event path, `:963` group path), and §2 omits the key when null. In Firestore rules, accessing an **absent** map key denies the whole condition — a direct `data.groupSettleUpId == null` would reject every keyless settlement write, i.e. ALL existing settle-ups (`settle_up_screen.dart` event settle, self-settle, creditor-records #282, every group settlement without the link). The codebase convention for optional fields is the `!('x' in data) ||`-first guard (`firestore.rules:305-308, 621-622`, comment `:84-85`); always-present fields like `note`/`deletedAt` (`:116-118`) are accessed directly — `groupSettleUpId` is NOT always-present, so it MUST be guarded.

**3b. Relax event-settlement-create authz** (`validEventSettlementCreate`, `:768-777`):
- Change `isEventParticipant(groupId, eventId)` → `isGroupMember(groupId)`.
- KEEP `data.payerParticipantId in participants()` and `data.recipientParticipantId in participants()` (`:756-757`) — the counterparties must still be event participants.

**Security argument (the Gate WILL scrutinize this — and the `/automerge` reviewer checks this exact sentence):** Today any group member may already create a GROUP settlement between any two members (`validGroupSettlementCreate` needs only `isGroupMember`, parties `in memberIds`). The relaxed event rule requires the writer be `isGroupMember` and both parties `in participants()` (the event's `participantIds`). **[Gate R4 P2 — precise] This is NOT a strict subset of group-settlement permissions:** `participants()` can include a departed event-participant who is no longer `in memberIds` (the #249 case), whom `validGroupSettlementCreate` would reject. So the relaxed rule admits a *slightly different* set, not a narrower one. It is nonetheless safe: (i) the parties are real prior event participants (not arbitrary), (ii) settlements are append-only and correctable by an offsetting row, (iii) `firestore.rules` is a shape-gate not a value-gate either way, and (iv) it matches the #595 "any member may record a transfer between two others" model. An attacker gains nothing they could not already do via a group settlement. `validEventSettlementUpdate` is dead (allow update:if false) — leave it. Nothing relies on event-settlement `createdBy` being an event participant (audit logger doesn't fire on settlements; `settlementNotifier` already handles third-party recorders, `targets = {payer,recipient}\{createdBy}`). **[Gate R2 P3 — writer-axis note]** vs the OLD event rule this is a *swap*, not a strict superset: a departed-but-still-event-participant **non-member** writer LOSES the ability to write event settlements (was `isEventParticipant`, now `isGroupMember`). This is benign/desirable (a non-member should not write into a group's ledger) and consistent with every other group-scoped write, but note it explicitly.

**Tests (emulator, RED first):**
- A group member who is NOT a participant of event E can now create an event settlement in E between two event participants (was permission-denied).
- A non-member still cannot.
- An event settlement carrying `groupSettleUpId` (string) is accepted; a non-string is rejected; absent is accepted.
- A group settlement carrying `groupSettleUpId` is accepted.
- Re-run `firestore-rules-publish-readiness.test.ts` expectations.

**Deploy:** rules only (oracle/functions unchanged). Project rule "no real users yet → deploy freely" applies; use the `deploy-ceremony` skill; advance the `backend-deployed` tag.

---

## 4. Write orchestration — decompose the record path

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (`_recordSettlement`, `:525-661`)
- Test: `test/features/groups/group_settle_up_decompose_test.dart` (new, fake Firestore)

**Design — three funnels, do NOT edit `_recordSettlement` in place:** `_recordSettlement` (`:525`) is called by THREE entry points, not two: `onRecord` (single tile, via `_showRecordPaymentSheet`), `onRecordStepped`→`_runSteppedSettle` (via `_showRecordPaymentSheet`), **and `onCorrect` directly (`:193-204`)**. A naive in-place edit of `_recordSettlement` to decompose would wrongly decompose corrections too. **[Gate R1 P2]** Instead:
- Keep `_recordSettlement` as the **raw single group-doc write primitive** (one `addGroupSettlement`, no decompose) — reused for the residual write and as a building block.
- Add a new `_recordDecomposedSettlement(...)` that does the allocator → N event writes → residual (see steps below). Point `_showRecordPaymentSheet` (`:510`) at `_recordDecomposedSettlement` so the single-tile + stepped paths decompose.
- Add a raw event-settlement primitive (`_recordEventSettlement`, wrapping `SettlementService.addSettlement` with the same try/catch + ack + connectivity discipline as `_recordSettlement`) — used by the decompose (§4).
- **`onCorrect` is UNCHANGED in PR1.** It keeps calling `_recordSettlement` (single group-doc reverse). The §5b correct affordance is hidden for `groupSettleUpId`-tagged settlements, so `onCorrect` only ever receives a legacy/standalone group settlement → a correct single-doc reverse. Corrections-of-decomposed are PR2 (§6).

The per-currency stepping (`_runSteppedSettle`) is unchanged (each step is one currency; the decompose happens inside that step's `_recordDecomposedSettlement` call).

**Orchestration (one logical settle-up):**
0. **[Gate R2 P1 — live-membership pre-gate, load-bearing] Decompose ONLY if BOTH `fromUserId` and `toUserId` are live group members** (present in the group doc's `memberIds` — the set the residual rule checks at `firestore.rules:952-953`). If either is NOT a live member, **fall back to the single `addGroupSettlement`** (today's path) and return. Rationale: the residual group settlement requires both parties `in memberIds`, but event settlements only require `in participants()` (`:756-757`). A #249 departed-but-still-event-participant party would pass the event writes yet get **permission-denied** on the residual — and with events-first/stop-on-error (step 4) that leaves a **partially-persisted** settle-up + a permanently stuck residual + an error on every retry, where today the single group write fails **atomically** (clean, nothing persisted). Gating on live membership preserves today's atomic behavior for departed-member transfers (a pre-existing limitation: you already cannot settle with a departed member at the group level — the single write is denied too — so the fallback changes nothing for them) while enabling decompose for the all-live common case (where every write provably succeeds: both ∈ `memberIds` ⇒ residual OK; both ∈ attributed-event `participants()` by construction ⇒ event writes OK). **[Gate R3 P2 — pin the set]** read the gate from **`group.memberIds`** (the `Group` model array, `group_model.dart`, the EXACT set the residual rule checks at `firestore.rules:952-953`), NOT from `groupMembersProvider` (an independent member-subcollection stream that can diverge from the array). A superset source would reintroduce the partial-persist this gate prevents. (Shadows are safe — `addShadowMember.ts` `arrayUnion(newId)` puts them in `memberIds`.) The group doc is already in scope on this screen (`groupDetailProvider`).
1. Mint one `groupSettleUpId = const Uuid().v4()`.
2. `eventOrder = ` the group events list order (already available via `groupEventsProvider`; pass it in — it is the same order the display breakdown uses, guaranteeing display == write).
3. `(perEvent, residual) = BalanceCalculator.decomposeGroupSettlement(payerPerEventNet: balancesData.perEventBreakdown[fromUserId] ?? {}, recipientPerEventNet: balancesData.perEventBreakdown[toUserId] ?? {}, currency: currency, amount: amount, eventOrder: eventOrder)`.
4. **Events first, residual last.** For each `entry in perEvent` (in `eventOrder`): `await awaitServerAck(SettlementService.addSettlement(groupId, eventId, payer=fromUserId, recipient=toUserId, amount=entry.value, currency, createdBy=currentUid, payerName=fromName, recipientName=toName, note, groupSettleUpId), skipWait: offline)`. On error → STOP (append-only; recorded rows stay; re-entry recomputes — §4 re-entry note). 
5. If `residual > 0`: write the residual group doc. **[Gate R4 P2] Once-semantics:** the per-doc writes (N event + residual) must each run as RAW writes with `logActivity:false` AND `showSuccessSnackbar:false` — do NOT reuse `_recordSettlement`'s defaults (it logs `group_settlement` with amount=the-residual and snackbars per call; a literal reuse would log the residual amount, or log NOTHING when residual==0, and double-snackbar). The orchestration logs the activity ONCE (`group_settlement`, amount=A) and shows ONE success/queued snackbar, after the walk.
6. **Bump `ledgerRevisionProvider` after EACH successful event write** (`ref.read(ledgerRevisionProvider.notifier).state++`), not only after all of them. **[Gate R2 P3]** REQUIRED: the home one-shot path (`groupBalancesOnceProvider` watches it, `group_balance_provider.dart:684`) reads event settlements; without the bump the home balance goes stale, and bumping per-write keeps home fresh even if the walk stops mid-way on a partial failure. (The group path historically skipped the bump because group settlements are live-watched — that no longer holds once we write event docs.)
7. Connectivity notes (`noteLocalWrite`/`noteQueuedWrite`) and the activity log (`group_settlement` once per logical settle-up, amount=A, not per row) as today.
8. Success/queued snackbar once per logical settle-up (not per row).

**Edge cases:**
- `perEvent` empty AND `residual > 0` (pure cross-event / no shared event): writes only the residual group doc — identical to today's behavior for that transfer. ✓
- `perEvent` non-empty AND `residual == 0` (common single-event): writes only event docs, no group doc. History still shows it via §5 (groupSettleUpId regroup). ✓
- Partial edit (`amount < suggested`, allowed at `:497`): allocator caps at the edited amount; residual ≥ 0. The tile breakdown (shown pre-sheet at the *suggested* amount) may show more rows than written — document; the common full-settle case is exact WYSIWYG. (Open question Q1.)

**Re-entry / partial-failure (reuse `_runSteppedSettle` discipline):** a failed write stops the walk; written rows persist (append-only). On re-entry the live `perEventBreakdown` now reflects the written event settlements (their per-event net shrank), and the aggregate suggested amount shrank by the written total, so `decomposeGroupSettlement` naturally attributes only the remainder. Events-first/residual-last keeps every intermediate state consistent (event ledgers and aggregate move together). **[Gate R1 P3 — accepted cosmetic]** a re-entry mints a FRESH `groupSettleUpId`, so a partially-failed-then-completed settle-up splits into two logical history rows. Money is correct; this is cosmetic and accepted for v1 (persisting an in-progress id to resume is out of scope).

---

## 5. Display + group-level history

**5a. Tile breakdown via the shared allocator** (`group_settle_up_screen.dart:_buildPerEventBreakdown:297`):
- Reimplement to call `decomposeGroupSettlement(...)` at the tile's suggested amount, then map eventId→label (`_buildEventLabel`) for the per-event rows, and append a **residual row** ("Across events" / group-level) when residual > 0.
- **[Gate R1 P2 — WYSIWYG pin] The display MUST pass the IDENTICAL `eventOrder` as the write (§4 step 2).** The allocator's per-event split is order-dependent on cap exhaustion (case 5: `[E1,E2]→{E1:3,E2:3}` vs `[E2,E1]→{E2:5,E1:1}`; totals/residual are order-invariant, so money is never wrong — but displayed rows must equal written rows). The current `_buildPerEventBreakdown` iterates a **set-union** `{...fromBreakdown.keys, ...toBreakdown.keys}` (`:308`) — REPLACE that with the same `eventOrder` (the `groupEventsProvider` events-list order) the write uses. Pass `eventOrder` into both the `buildBreakdown` closure and the write so they cannot diverge.
- This makes displayed == written for the full-amount case and fixes the current over-display (case 2 shows 6, not 10). Add l10n key for the residual row label.
- Keep returning `Map<String, Decimal>` to `SettleUpPageBody.buildBreakdown` (label-keyed for display). The WRITE path (§4) calls the allocator directly with eventId keys — do NOT reuse the label-keyed display map for writes (labels are lossy/collidable — agent-confirmed).

**5b. Group history — union tagged event settlements (PR1: individual rows, NOT regrouped)** (`settle_up_page_body.dart:_PaymentHistorySection`, and the data feeding it):
- **The regression to fix:** a single-event settle-up writes 1 event settlement + 0 residual, so the group history (group docs only, `group_settle_up_screen.dart:95-97,151`) would show NOTHING. PR1 fixes this by **unioning the `groupSettleUpId`-tagged event settlements into the group history**, sorted by `settledAt` newest-first, each rendered as an **individual `_HistoryTile`** (no logical regroup in PR1). Common single-event case → exactly one history row (the event settlement) — no vanish. Multi-event → N+1 rows (cluttered but honest; the one-logical-row regroup is a PR2 nicety that corrections need anyway).
- **No `onCorrect` signature change, no `LogicalSettlement` type in PR1.** `SettleUpPageBody.onCorrect` stays `void Function(Settlement settlement)` (`settle_up_page_body.dart:188`) — it is SHARED by the event settle-up screen (`settle_up_screen.dart:309`), so changing it would break that screen.
- **Correct affordance:** the one-tap "correct" button (`_HistoryTile`, `:891-914`) must be **HIDDEN when `settlement.groupSettleUpId != null`** (a decomposed doc — reversing it via the group-only `onCorrect`→`addGroupSettlement` path would move the aggregate but NOT the event ledger, re-introducing the divergence). Legacy/standalone group settlements (null id) keep the button (today's correct behavior — a single group doc reverse). Since there are NO real users yet, no existing correctable data is affected; only newly-recorded decomposed settle-ups lack one-tap correction until PR2. (Users can still record a manual offsetting transfer.) **[Gate R4 P3 — note]** `_HistoryTile` is SHARED with the event settle-up screen (`settle_up_screen.dart:309`), so a tagged event-settlement slice also appears on its own event's settle-up history and likewise loses the one-tap correct button there. Intended: a group settle-up's slice should not be piecemeal-corrected from inside one event (PR2 corrects the whole logical settle-up atomically).
- Source of tagged event settlements: already fetched by `groupBalancesProvider` (`allEventSettlements`, `group_balance_provider.dart:148,167`) but not exposed in the `GroupBalances` typedef (`:86-93`). Add `allEventSettlements` to that record (additive; thread through `computeGroupBalances`). The group screen builds the unioned history list (`[...groupSettlements, ...allEventSettlements.where((s) => s.groupSettleUpId != null)]`, sorted) and passes it as `settlementsAsync`. The event screen is UNCHANGED (passes its own event settlements).
- **[Gate R3 P2 — all-settled interaction]** the `allSettled` gate is `totalTransfers == 0 && history.isEmpty` (`settle_up_page_body.dart:213`). Unioning tagged settlements into `history` only ADDS rows, so `allSettled` stays correct (a settled group with recorded payments already had a non-empty history). No regression; pin with a test that a fully-settled single-event group shows the settle-up in history and the all-settled state.

---

## 6. Corrections (#283) of decomposed settle-ups — DEFERRED to PR2 (fast-follow, own Gate)

**Decision (owner, 2026-06-29):** split. The Gate (round 3) showed corrections-of-decomposed is a separate hard problem and bundling it risks the release-blocker. **PR1 does NOT implement corrections-of-decomposed.** Instead, PR1 hides the one-tap correct affordance on `groupSettleUpId`-tagged settlements (§5b) — so nothing half-corrects — while legacy/standalone corrections keep working unchanged. No real users yet ⇒ no existing correctable data is stranded.

**PR2 scope (separate issue + its own Gate cycle):**
- Reverse ALL docs of a logical settle-up **atomically** — a single Firestore `WriteBatch` spanning the N event-settlement subcollections + the group-settlement collection in one commit (rules-checked + offline-queued atomically). This is the round-3 [P1] fix: a sequential `awaitServerAck`-per-doc walk is NOT atomic (partial reversal) and re-entry double-reverses a FIXED doc list (corrections, unlike §4, have no recompute-on-re-entry self-heal).
- Resolve the shared `onCorrect` callback: the event settle-up screen (`settle_up_screen.dart:309`) shares `SettleUpPageBody.onCorrect`; PR2 must give the group screen a logical-correction path without breaking the event screen's single-`Settlement` contract.
- Logical-row regroup in history (one "settled A with X" row per `groupSettleUpId`) — needed so the user corrects the whole settle-up, not one slice.
- Idempotency: a re-tapped correction must not double-reverse.
- Live-membership at correction time (a party may depart between record and correct).

**Tracked as a fast-follow issue (filed before PR1 merges) so it is not a Schrödinger's fix** (CLAUDE.md: a deferred fix lives in a named milestone, never a memory note).

---

## 7. Tests (the release-blocker bar)

- **RED regression (the user's repro):** a group settle-up P→R reduces the affected event ledger. Most natural home: a widget/provider test on `ledgerViewProvider`/event balance showing a decomposed event settlement now reduces the event's owed. Write RED first; watch it fail against current code (group settlement does nothing to the event); GREEN after decompose.
- **Allocator units** (§1) — table-driven, incl. the negative-residual guard.
- **Parity test:** `decompose writes` vs `one group doc` produce identical aggregate nets via `computeGroupBalances` (mirror `settle_up_correction_balance_567_test.dart` style). Pin `Σ(per-event) + residual == A`.
- **Rules emulator** (§3).
- **History union** widget (§5b): a single-event group settle-up shows exactly one history row (the event settlement) — no vanished payment. **[Gate R4 P2 — precise assertion]** for a fully-settled single-event group, assert the "everyone even" headline (`transferCount==0`, `settle_up_page_body.dart:213,399-401`) + the history row is present — do NOT assert `find.byType(AllSettledState)` (that widget is correctly HIDDEN once `history` is non-empty: `allSettled = totalTransfers==0 && history.isEmpty`; same as today's group-settlement path, so no regression — an implementer must not "fix" the gate).
- **Correct affordance hidden on tagged** (§5b): a `groupSettleUpId`-tagged settlement shows NO correct button; a legacy/standalone group settlement (null id) DOES, and its correction still reverses correctly.
- **Departed-member fallback** (§4 step 0): a settle-up involving a departed-but-event-participant party does NOT write event settlements — it falls back to the single `addGroupSettlement` (no partial-persist).
- **Offline (#412):** model a never-completing write through a mocked service; assert queued + `ledgerRevision` bumped (FakeFirebaseFirestore acks instantly, proves nothing — CLAUDE.md).
- Update the existing tests flagged by the inventory: `group_balance_provider_test.dart` (per-event pins stay valid — read path unchanged), `group_settle_up_screen_test.dart` (`addGroupSettlement` recorder now also sees `addSettlement` calls; stepped-walk assertions), `delete_group_balance_parity_test.dart` (whole-subunit residual parity).

---

## 8. The 7 verification principles (applied — report)

1. **Classify callsites (INBOUND/OUTBOUND/BOTH).** `perEventBreakdown` read by the allocator = INBOUND (display + suggestion). The allocator output OUTBOUND (feeds writes). `groupSettleUpId` BOTH (written + read for history/corrections). Event-settlement write OUTBOUND. Display label map INBOUND-only (never a write key).
2. **Verify every concrete claim against code.** Done — every file:line above re-confirmed in-session (paths, rules lines, oracle fold lines, aggregator triggers).
3. **Trace one read-path per write-path.** Event-settlement write → read by `eventSettlementsProvider`→`ledgerViewProvider` (event ledger), by `groupBalancesProvider`/`groupBalancesOnceProvider` (group + home), and by `recomputeNet` (server aggregate). Residual group write → `groupSettlementsProvider` + oracle global fold. `groupSettleUpId` write → history regroup + corrections read.
4. **Enumerate fields from the type.** `Settlement` fields enumerated (§2). Event-settlement rule `hasOnly` (13 keys) and group `hasOnly` (15 keys) enumerated (§3).
5. **Spell out data contracts.** Allocator signature + record return type (§1); `addSettlement`/`addGroupSettlement` new param (§2); rule field type (§3); `LogicalSettlement`/history grouping (§5b).
6. **Verify arithmetic decomposition.** `Σ per-event subunits + residual subunits == toSubunits(A)` is the allocator's pinned invariant (§1). Aggregate equivalence proven in §0.2 (payer += Σa_e + r = A). **Caution honored:** this asserts the *transfer* A decomposes; it does NOT claim `netMilli == Σ perEventNetMilli` (that still fails by design — residual + participantIds-only universe). Update CLAUDE.md wording, not the rule.
7. **Adversarial pass on an orthogonal axis.** Fix is on the per-event *attribution* axis; the worked negative-residual example exercises the **cross-event settlement/identity axis** (payer is debtor in E1, creditor in E2). Also exercise the **authz/identity axis** (settle-on-behalf writer ∉ event participants) and the **time axis** (partial-failure re-entry recompute).

---

## 9. Risks / Gate-must-verify

- [ ] Allocator never emits negative/over-cap; Σ + residual == A in subunits (incl. JPY scale 1, OMR sub-subunit).
- [ ] Authz relaxation grants nothing beyond existing group-settlement permission; payer/recipient still gated to event participants.
- [ ] `ledgerRevisionProvider` bump present on the new event-write path (home staleness).
- [ ] Group history shows the settle-up after decompose (no vanished payment in the single-event/residual-0 case) — via the tagged-event-settlement union (§5b).
- [x] Corrections: **DEFERRED to PR2 (Gate R3).** PR1 hides the one-tap correct affordance on `groupSettleUpId`-tagged settlements so nothing half-corrects; legacy/standalone corrections unchanged. Fast-follow issue filed before PR1 merges.
- [ ] Oracle/`recomputeNet` and `balanceAggregator` untouched; `groupSettleUpId` ignored by the oracle (unknown field).
- [ ] N+1 push notifications per decomposed settle-up (`settlementNotifier` fires per doc) — confirm acceptable UX or debounce (Open question Q4).
- [ ] Multi-currency: decomposition strictly per-bucket; never sum across currencies.
- [x] Departed-member edges (#249/#216): **RESOLVED (Gate R2 P1)** — a departed (#249) party is NOT in `memberIds`, so the residual group write would be permission-denied. The §4 step 0 live-membership pre-gate routes any transfer with a non-live party to the single `addGroupSettlement` fallback (today's atomic-fail behavior), so decompose never partially-persists. Pin with a test: a settle-up involving a departed-but-event-participant party does NOT write event settlements (falls back).
- [ ] `eventId == groupId` sentinel retained on the residual (#71); event docs keep `eventId == eid`, no `scope` field.

## 10. Open questions (resolve in/after the Gate)
- **Q1 (partial edit WYSIWYG):** show the breakdown at the suggested amount and re-allocate on a partial edit (documented), or recompute the displayed breakdown live in the record sheet? Default: documented re-allocate.
- **Q2 (history scope): RESOLVED** — group history shows `groupSettleUpId`-tagged event settlements + group docs (directly-recorded event settlements stay out, preserving today's group-history meaning). PR1 = individual rows; PR2 = logical regroup.
- **Q3 (corrections phasing): RESOLVED (owner, 2026-06-29)** — fast-follow (PR2). PR1 hides the correct affordance on tagged settlements (no half-correct).
- **Q4 (notification fan-out + per-doc amounts):** **[Gate R1 P2]** each event-settlement create fires `eventSettlementNotifier` (`settlementNotifier.ts:83-86`) with the per-doc `amountFils` (`a_e`), so a decomposed settle-up of 10 across 3 events pushes the counterparty "settled 3 / 3 / 4", not one "settled 10" — confusing, though money is correct. Options: accept N+1 partial-amount pushes for v1; OR suppress the per-event notifier when `groupSettleUpId` is present and send one summary push for the logical settle-up (a `settlementNotifier.ts` change — but that's a Functions edit, breaking "deploy rules only"; defer). Default: accept for v1 (detection-only rate monitor never blocks); revisit if QA finds it jarring.

## 11. Sequencing — PR1 (release-blocker; each slice leaves the tree green)
1. Allocator + unit tests (§1).
2. Schema field + service params + tests (§2).
3. Rules relaxation + field allow-list + emulator tests + **deploy** (§3, `deploy-ceremony`).
4. Write orchestration (incl. live-membership pre-gate, events-first/residual-last, per-write `ledgerRevision` bump) + decompose tests + RED regression GREEN + departed-member fallback test (§4, §7).
5. Display breakdown via allocator + residual row, pinned to the same `eventOrder` as the write (§5a).
6. History union (tagged event settlements) + correct-button-hidden-on-tagged + tests (§5b).
7. Docs: update CLAUDE.md balance-aggregate gotcha wording + `group_balance_aggregate_model.dart` comment (principle 6 caveat).
8. `flutter analyze` clean, full suite, `tool/check_theme_purity.sh`, then `/automerge` (Gate-category → fresh-Opus review path). PR body carries `Refs #752` (PARTIAL — corrections deferred; keep #752 open re-scoped, and put `Refs #752` in the COMMIT message too, not just the PR body — squash-merge auto-closes from the commit body).

**PR2 (fast-follow, own spec + Gate):** corrections-of-decomposed via atomic `WriteBatch` (§6). Filed as a new issue before PR1 merges.
