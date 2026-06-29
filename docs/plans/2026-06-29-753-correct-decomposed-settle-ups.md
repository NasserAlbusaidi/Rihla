# #753 — Atomic corrections of decomposed group settle-ups — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. This plan is **Gate-category** (money write path + WriteBatch atomicity + a shared callback contract). Do NOT implement until the fresh-context Opus Gate verdict has zero [P1]s.

**Goal:** Restore the one-tap "correct" affordance on a **decomposed** group settle-up (the `groupSettleUpId`-tagged set PR1 hid it on), reversing **all N event-settlement docs + the residual group doc of one logical settle-up in a single atomic `WriteBatch`** — so the per-event ledgers and the group/home aggregate re-open together, never partially.

**Architecture:** PR1 writes one logical group settle-up as N event settlements + ≤1 residual group settlement, all sharing a `groupSettleUpId = X`. PR2 corrects it by writing, in **one `WriteBatch`**, an offsetting reverse of **each original doc** (swap payer↔recipient, same amount/currency/eventId, carrying the **same `groupSettleUpId = X`** + the localized correction-note sentinel). The reverses being tagged `X` makes the logical history row self-describing: a settle-up is "already corrected" iff its group contains a correction-note doc — which is the **idempotency guard** (the affordance hides; the callback no-ops). Group history **regroups** all docs sharing an `X` into **one logical row** so the user corrects the whole settle-up, not a slice. **This is a CLIENT-ONLY change** — the reverse writes are already valid under PR1's deployed rules (`groupSettleUpId` allow-listed; `validEventSettlementCreate` relaxed to `isGroupMember`; both reverse parties are the originals' parties, still `in participants()`/`in memberIds`). No schema field, no rules change, no backend deploy.

**Tech Stack:** Flutter / Riverpod 2.x (no codegen), `decimal`, Firestore `WriteBatch`, `MoneySerializer` (integer subunits at the boundary), `awaitServerAck` (#412 race), `flutter_test` + `fake_cloud_firestore`. The server oracle is **untouched** (it already folds reverses: event reverses per-event, the residual reverse globally, by collection path).

---

## 0. Verified context (code, not docs — re-confirm before each task)

Verified against live code on 2026-06-29 in this worktree (branch `feat/752-decompose-group-settlements`, PR #754). **Implement PR2 on a branch stacked on PR1's branch** (`feat/752-decompose-group-settlements`) so the decompose code is present; base the PR on `feat/752-decompose-group-settlements` (GitHub auto-retargets to `main` when PR1 merges).

### 0.1 What PR1 left (confirmed)
- One logical settle-up = N event settlements (`groups/{gid}/events/{eid}/settlements`, `scope`=='event') + ≤1 residual group settlement (`groups/{gid}/settlements`, `scope`=='group', `eventId`==`groupId` sentinel), all carrying `groupSettleUpId == X`. Write site: `group_settle_up_screen.dart:601` `_recordDecomposedSettlement`.
- Group history unions group docs (`groupSettlementsProvider`) with `groupSettleUpId`-tagged event docs (`groupTaggedEventSettlementsProvider`, `group_balance_provider.dart:226`), sorted newest-first (`group_settle_up_screen.dart:103-109`), rendered **per-doc** by `_PaymentHistorySection`/`_HistoryTile` (`settle_up_page_body.dart:645-965`).
- PR1 **hides** the one-tap correct button on any `settlement.groupSettleUpId != null` doc (`settle_up_page_body.dart:900-905`). Legacy/standalone group settlements (null id) keep one-tap correct via the shared `onCorrect: void Function(Settlement)` (`settle_up_page_body.dart:191`), wired to `_recordSettlement` with a payer↔recipient swap + the `settleUpCorrectionNote` sentinel (`group_settle_up_screen.dart:222-233`).

### 0.2 The existing single-doc correction model (the contract to extend, not break)
- A correction = ONE offsetting reverse settlement: swap payer↔recipient, same amount + currency, `note = l10n.settleUpCorrectionNote`. **Append-only — the original stays.** Pinned by `settle_up_correction_test.dart` + the pure money parity in `settle_up_correction_balance_567_test.dart` (original + reverse net to zero in the same per-currency bucket → debt re-opens).
- The reverse renders as a separate **"Correction"** row: `_isCorrectionNote(note)` matches a **locale-spanning** sentinel set (`settle_up_page_body.dart:687-695`) — `_correctionNoteSentinels` = the note in EVERY supported locale (#567), so a corrector's-locale note is recognized by any viewer.
- `onCorrect` is **SHARED** by the event settle-up screen (`settle_up_screen.dart:309-320`, gated `canRecord`). Its signature `void Function(Settlement)` **must not change** (Gate/issue constraint).
- **No idempotency today:** tapping correct twice records two reverses (over-corrects). PR2 ADDS idempotency for the logical path.

### 0.3 Why a single atomic WriteBatch (the round-3 [P1] this PR exists to fix)
A sequential `awaitServerAck`-per-doc reverse walk (like the record path) is **wrong for corrections**: (a) it is **not atomic** — a mid-walk failure leaves some events reversed and others not (divergent ledgers), and (b) corrections reverse a **FIXED doc list** with **no recompute-on-re-entry self-heal** (the record path re-derives the remaining amount from live streams; a correction re-run would reverse the same docs **again** → double-reverse). A Firestore `WriteBatch` commits all-or-nothing **including the rules check** (if any reverse violates rules, none apply) and is queued/replayed atomically offline (#412). That is the whole reason the issue mandates a batch.

### 0.4 Why CLIENT-ONLY (no rules/schema/deploy)
The reverse docs reuse the **existing** `groupSettleUpId` field (allow-listed in PR1) and the **existing** correction-note string (free text). Each reverse is a normal settlement create:
- Reverse EVENT settlement in `E_i`: writer is a group member; parties (R,P) were the originals' parties, hence still `in participants(E_i)` → valid under PR1's relaxed `validEventSettlementCreate`.
- Reverse RESIDUAL group settlement: writer is a group member; parties (R,P) `in memberIds` (if both still live) → valid under `validGroupSettlementCreate`.

So PR2 ships no rules/schema and needs no backend deploy. It does inherit PR1's deploy for the **third-party-member** correction case (a non-participant member correcting needs the relaxed event rule); a **self-correction** (corrector ∈ {payer, recipient}, who are event participants of every attributed event by construction) is valid even pre-deploy — same deploy-dependency profile as PR1's record path.

---

## 1. KEYSTONE — the atomic reverse primitive (`SettlementCorrectionService.reverseLogicalSettleUp`)

**Files:**
- Create: `lib/features/groups/services/settlement_correction_service.dart`
- Create: `test/features/groups/settlement_correction_service_test.dart`
- Modify: `lib/features/groups/providers/group_balance_provider.dart` (add `settlementCorrectionServiceProvider`) — OR co-locate the provider with the service file's feature; pick the provider file the screen already imports.

**Why a new service (single responsibility, one `db`, testable):** the batch spans BOTH the event subcollections and the group collection, so it must be built from a **single** `db` (one `WriteBatch` cannot span two `FirebaseFirestore` instances). Neither existing service owns both paths; a dedicated `FirestoreRepository` subclass builds both ref kinds from its own `db` (mirrors `group_provider.dart:218`'s `db.batch()` create pattern).

**Contract (exact):**

```dart
/// Atomically reverses every doc of ONE logical group settle-up (#753).
///
/// [originals] MUST be exactly the non-correction docs sharing one
/// `groupSettleUpId` (the caller filters; see §3 idempotency). Each is reversed
/// (swap payer↔recipient, same amount/currency, same destination collection)
/// and tagged with the SAME [groupSettleUpId] + [correctionNote] so the logical
/// history row shows "corrected" and a re-tap is a no-op. All reverses commit in
/// ONE `WriteBatch` — all-or-nothing, rules-checked + offline-queued atomically.
///
/// Returns the commit future so the caller can race it with [awaitServerAck]
/// (#412). Throws (FirebaseException / StateError) if the batch is rejected —
/// the caller surfaces it; NOTHING is persisted (atomicity).
Future<void> reverseLogicalSettleUp({
  required String groupId,
  required String groupSettleUpId,
  required List<Settlement> originals,
  required String correctedBy,   // auth uid; rules require createdBy == auth.uid
  required String correctionNote, // l10n.settleUpCorrectionNote (corrector's locale)
});
```

**Implementation sketch:**

```dart
class SettlementCorrectionService extends FirestoreRepository {
  SettlementCorrectionService() : super();
  @visibleForTesting
  SettlementCorrectionService.withFirestore(super.db) : super.withFirestore();

  Future<void> reverseLogicalSettleUp({
    required String groupId,
    required String groupSettleUpId,
    required List<Settlement> originals,
    required String correctedBy,
    required String correctionNote,
  }) {
    if (correctedBy.isEmpty) {
      throw ArgumentError.value(correctedBy, 'correctedBy', 'auth uid required');
    }
    final batch = db.batch();
    final now = DateTime.now().toUtc();
    for (final s in originals) {
      final newId = const Uuid().v4();
      final isResidual = s.scope == 'group';
      final ref = isResidual
          ? db.collection('groups').doc(groupId).collection('settlements').doc(newId)
          : eventSubcollection(groupId, s.tripId, 'settlements').doc(newId);
      final data = <String, dynamic>{
        'id': newId,
        // event reverse → real eventId (s.tripId); residual reverse → groupId sentinel
        'eventId': isResidual ? groupId : s.tripId,
        if (isResidual) 'scope': 'group',
        if (isResidual) 'groupId': groupId,
        // SWAP parties
        'payerParticipantId': s.recipientParticipantId,
        'recipientParticipantId': s.payerParticipantId,
        'payerName': s.recipientName,
        'recipientName': s.payerName,
        'amountFils': MoneySerializer.toSubunits(s.amount, s.currency),
        'currency': s.currency,
        'note': correctionNote,
        'isDeleted': false,
        'deletedAt': null,
        'settledAt': now.toIso8601String(),
        'createdBy': correctedBy,
        'groupSettleUpId': groupSettleUpId,
      };
      batch.set(ref, data);
    }
    return batch.commit();
  }
}
```

> **[verify-before-write]** the residual-group write shape MUST match `GroupSettlementService.addGroupSettlement` EXACTLY (keys `scope`, `groupId`, `eventId`==groupId sentinel) or `validGroupSettlementBase.hasOnly([...])` rejects it. The event-reverse shape MUST match `SettlementService.addSettlement` (no `scope`/`groupId` keys) or `validEventSettlementBase.hasOnly` rejects it. Enumerate both `hasOnly` lists from `security/firestore.rules` and diff field-by-field before writing the test (verification principle 4). The reverse carries `groupSettleUpId` — already in both allow-lists (PR1).

**Tests (write FIRST, RED) — `fake_cloud_firestore`, money code → clean/parity cases:**
1. **Atomic write count:** seed 2 event-settlement originals (E1=3.000, E2=2.000) + 1 residual (1.000), all tagged `X`, P→R. Call `reverseLogicalSettleUp`. Assert: each event subcollection gains exactly ONE reverse (R→P, same amount, `groupSettleUpId==X`, note==sentinel); the group collection gains ONE reverse residual. (6 docs total: 3 original + 3 reverse.)
2. **Balance re-opens (parity, the #567 analog):** build `computeGroupBalances` over an expense that left P owing R; after the original decomposed settle-up nets P/R to zero; after `reverseLogicalSettleUp` the per-currency net re-opens to the pre-settle values. (OMR scale 1000 + USD scale 100, table-driven.)
3. **No residual case:** originals = 1 event doc only (residual was 0). Reverse writes exactly 1 event reverse; group collection untouched.
4. **Reverse path fidelity:** the event reverse lands in the SAME event subcollection (`s.tripId`), not the group collection; the residual reverse lands in the group collection, carries `scope=='group'` + `eventId==groupId`.
5. **createdBy empty → ArgumentError** (mirrors the services' guard).

> **Atomic-rules-failure is NOT unit-testable** — `fake_cloud_firestore` does not run rules, so the all-or-nothing-on-rejection property is asserted by the WriteBatch semantics + the §4 departed-party reasoning, not a fake test. (Document; do not fake a green that proves nothing — CLAUDE.md.)

---

## 2. History regroup — one logical row per `groupSettleUpId`

**Files:**
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart` (`_PaymentHistorySection`, `_HistoryTile`)
- Test: `test/features/groups/settle_up_correction_test.dart` (extend), new `test/features/groups/settle_up_logical_history_test.dart`

**Pure grouping (extract a testable top-level fn):**

```dart
/// Collapses a settle-up history into display rows: each `groupSettleUpId`-tagged
/// set becomes ONE logical row (amount = Σ of its NON-correction docs); untagged
/// docs (legacy/standalone group settlements + their single-doc corrections) stay
/// individual rows, byte-identical to today. Order: newest-first by the row's
/// representative settledAt (max over the group).
@visibleForTesting
List<HistoryRow> groupSettlementHistory(List<Settlement> settlements);
```

`HistoryRow` (sealed-ish record):
- `solo(Settlement settlement)` — untagged; renders exactly as today (its own `onCorrect`, "Correction" label if note matches). **Untagged is never regrouped** → all existing untagged tests pass unchanged.
- `logical({String groupSettleUpId, Settlement representative, Decimal totalAmount, bool isCorrected, DateTime settledAt})` where:
  - `representative` = the first NON-correction doc tagged X (for payer/recipient/currency/ids).
  - `totalAmount` = Σ amounts of the NON-correction docs tagged X (= the logical A).
  - `isCorrected` = `members.any((s) => _isCorrectionNote(s.note))` — atomic reverse ⇒ presence implies the **whole** reversal committed (no partial). This is the **idempotency signal**.
  - `settledAt` = max settledAt over all docs tagged X.
  - **Defensive:** if a tagged group has ZERO non-correction docs (corruption / a reverse whose original was filtered out), fall back to rendering its members as `solo` rows — never crash, never show a phantom logical row.

**Rendering (`_PaymentHistorySection`):** map `groupSettlementHistory(settlements)` → for `solo` build today's `_HistoryTile(settlement:…, onCorrect:…)`; for `logical` build the new logical tile variant (below). Keep the `index==0` key on the FIRST row (`GroupKeys.settleUpCorrectButton` test hook) — but now that first row may be logical; the key must move to whichever correct affordance is rendered first (see §3).

**[Gate R1 P2 — confine the regroup to the group screen] Regroup ONLY when `onCorrectLogical != null`.** `_PaymentHistorySection` is SHARED with the event settle-up screen (`settle_up_screen.dart`), whose `settlements` are this-event-only (`eventSettlementsProvider`) — regrouping there would collapse a tagged slice into a "logical" row whose `totalAmount` is just `a_i` (this event's slice, missing the siblings + residual), a misleading partial. So gate the regroup on `onCorrectLogical != null`: the group screen wires it → regroups; the event screen leaves it null → **no regroup, PR1 per-doc rendering unchanged** (a tagged slice renders as a payment row with its single-doc correct button hidden by the `groupSettleUpId != null` guard at `:900-905` — exactly today's event-screen behavior). This makes the event screen provably unchanged (resolves open-Q3).

**`_HistoryTile` logical variant:** add optional fields used only when rendering a `logical` row: `Decimal? overrideAmount` (shows `totalAmount` instead of `settlement.amount`), `bool isLogicalCorrected`, `VoidCallback? onCorrectLogical`. The dialog (`_confirmAndCorrect`) must use the **logical total** for its amount string. Minimal churn: keep passing the `representative` Settlement for names/date; override the amount + the correct callback.

> Keep the visual: a corrected logical row reads as a **"Correction"** row (reuse the `settleUpCorrectionTag` label + `Iconsax.undo` accent path, gated on `isLogicalCorrected || _isCorrectionNote`). An uncorrected logical row reads as a normal payment with the correct affordance.

---

## 3. Re-enable correction on the logical row + idempotency + the shared-callback split

**Files:**
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart` (new `onCorrectLogical` callback)
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (wire `onCorrectLogical` → batch reverse)
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` — **NO change** (leaves `onCorrectLogical` null → tagged slices stay uncorrectable on the event screen, by design: a group settle-up's slice must not be piecemeal-corrected from inside one event).
- Test: `test/features/groups/group_settle_up_decompose_test.dart` (extend) / a new `..._correct_test.dart`

**3a. The callback split (don't break the event screen):** add a SECOND optional callback to `SettleUpPageBody`:

```dart
/// #753: corrects a DECOMPOSED settle-up — reverses every tagged doc atomically.
/// The group screen wires this; the event screen leaves it null (a slice must not
/// be piecemeal-corrected). Distinct from [onCorrect] (single legacy/standalone
/// settlement) so the shared `void Function(Settlement)` contract is untouched.
final void Function(String groupSettleUpId)? onCorrectLogical;
```

The logical tile's correct button is shown iff: `onCorrectLogical != null && !isCorrected && representative.payerParticipantId/​recipientParticipantId both present`. Tapping → the SAME confirm dialog (total amount) → `onCorrectLogical!(groupSettleUpId)`.

**3b. The screen callback (`group_settle_up_screen.dart`):**

```dart
onCorrectLogical: (groupSettleUpId) => _correctLogicalSettleUp(
  context, group: group, groupSettleUpId: groupSettleUpId,
),
```

> **[Gate R1 P3] No `balancesData`** — the reverse uses each original's STORED amount (§4.6), never a re-decomposition, so the live balance is irrelevant to the callback. Don't thread it in (it would imply a re-decompose).

Screen state adds: `final Set<String> _correctingSettleUpIds = <String>{};` — the in-flight guard (next).

`_correctLogicalSettleUp(BuildContext, {required Group group, required String groupSettleUpId})`:
0. **Gather originals** = every settlement the screen already holds (group docs from `groupSettlementsProvider` ∪ tagged event docs from `groupTaggedEventSettlementsProvider`) where `groupSettleUpId == X` AND `!_isCorrectionNote(note)` AND `!isDeleted`. (Read the live provider VALUES synchronously via `ref.read(...).valueOrNull` — the same lists feeding history.)
1. **[Gate R1 P2 — in-flight guard, load-bearing] If `_correctingSettleUpIds.contains(X)` → return immediately.** This closes the double-tap-within-the-ack-window hole the stream-presence guard (step 2) does NOT cover: two confirms before the reverse stream emits would each gather the same `originals` and commit two reverse batches → over-correction (P ends `+A` wrong money). Because Dart is single-threaded, the first invocation runs synchronously through "add X to the set" (step 5) BEFORE its first `await`, so a second invocation (a later event) sees X and bails. The issue's explicit "a re-tapped correction must not double-reverse" requirement is met by THIS guard (not by the stream-presence guard alone — §5 must NOT claim the re-read guard covers it).
2. **Idempotency (already-corrected) guard:** if ANY doc tagged X already has `_isCorrectionNote(note)` → already corrected; no-op (return). (Belt to the button-hidden suspenders; covers re-entry after the stream emitted the reverse.)
3. **Empty guard:** if `originals` is empty → no-op (nothing to reverse).
4. **Resolve `correctedBy`** = `FirebaseConfig.currentUser?.uid` (try/catch fail-open to a party id, mirroring `_recordSettlement`), throw/abort if empty.
5. **`_correctingSettleUpIds.add(X)`** (synchronously, before any `await`); wrap the rest in `try { … } finally { _correctingSettleUpIds.remove(X); }`. (No `setState` — the set is callback-serialization state, not read by `build`; the button's hidden-when-corrected state already comes from the regroup.)
6. **`skipWait` = connectivity != online.** `ack = await awaitServerAck(correctionService.reverseLogicalSettleUp(groupId: ..., groupSettleUpId: X, originals: originals, correctedBy: uid, correctionNote: l10n.settleUpCorrectionNote), skipWait: skipWait)`.
7. **`ledgerRevisionProvider.notifier.state++` AFTER `awaitServerAck` RETURNS (acked OR queued)** — the reverses include EVENT settlements, which the home one-shot reads (`groupBalancesOnceProvider`); offline there is no server commit, so bump on RETURN (not "on commit") or the home balance stays stale offline. [mirrors `_recordDecomposedSettlement:705`]
8. Connectivity note (`noteQueuedWrite` if queued / `noteLocalWrite` if acked) once.
9. **NO activity log** — a reversal must not surface as a fresh feed payment (matches `_recordSettlement`'s `logActivity:false` correction path, `group_settle_up_screen.dart:222-233`).
10. Snackbar once (`settleUpRecorded` / `settleUpRecordedWillSync`). On throw → classified error snackbar (`settlementWriteErrorMessage`/`classifySettlementWriteError`) — atomic, nothing persisted. The `finally` clears the in-flight id either way.

**3c. Live-membership at correction time:** **handled by batch atomicity, not a pre-gate.** If a party departed AND a residual exists, the residual reverse needs both parties `in memberIds` → the rules reject it → the WHOLE batch fails → error snackbar, nothing persisted (clean). If a party departed and there is NO residual (pure event decompose), the event reverses only need `in participants()` (a departed event-participant still qualifies) → the correction still succeeds. **No correctness reliance on a pre-gate** (unlike the record path, which pre-gates because its sequential writes could partial-persist; the batch cannot). Document this; a pre-gate would be UX polish only (deferred — surface to the Gate).

---

## 4. The 7 verification principles (applied — report)

1. **Classify callsites.** `originals` (settlements read for reversal) = INBOUND→OUTBOUND (read to build the reverse write). The reverse docs = OUTBOUND. `groupSettleUpId` on reverses = BOTH (written + read by history regroup/idempotency). The history regroup map = INBOUND-only (display).
2. **Verify every concrete claim against code.** Done in §0 — every file:line re-confirmed in-session (`settle_up_page_body.dart:900-905` hide-guard; `:687-695` locale-spanning sentinels; `group_settle_up_screen.dart:222-233` correction swap; `group_balance_provider.dart:226` tagged provider; `settlement_model.dart` `scope`/`tripId` semantics; `firestore_repository.dart:39` `eventSubcollection`).
3. **Trace one read-path per write-path.** Reverse EVENT write → read by `eventSettlementsProvider`→`ledgerViewProvider` (event ledger re-opens), `groupTaggedEventSettlementsProvider` (history regroup), `groupBalancesOnceProvider` (home), `recomputeNet` (server aggregate). Reverse RESIDUAL write → `groupSettlementsProvider` + oracle global fold. Both also re-read by the idempotency regroup.
4. **Enumerate fields from the type.** Reverse doc fields enumerated against `SettlementService.addSettlement` (event shape) and `GroupSettlementService.addGroupSettlement` (group shape) field-by-field; both rule `hasOnly` lists to be diffed in §1 before writing.
5. **Spell out data contracts.** `reverseLogicalSettleUp` signature (§1); `onCorrectLogical: void Function(String)` (§3a); `HistoryRow` solo/logical shapes + `groupSettlementHistory` (§2). `onCorrect` UNCHANGED.
6. **Verify arithmetic.** `totalAmount = Σ(non-correction docs tagged X) == A`; the reverse of each original at its STORED amount ⇒ original + reverse net to zero per-doc, hence per-event and at the aggregate (the #567 parity, now per-decomposed-doc). The reverse uses STORED amounts, NOT a re-decomposition (re-decomposing against a shifted live balance would mis-reverse) — this is why reversing the fixed doc list is correct.
7. **Adversarial pass on an orthogonal axis.** Fix is on the **atomicity/identity** axis (reverse a fixed set as one unit). Worked examples must exercise the **time axis** (re-tap after correction = idempotent no-op; partial-record-split-into-two-Xs each independently correctable) and the **membership axis** (departed party + residual ⇒ atomic rules-fail, no partial; departed party + no residual ⇒ event reverse still valid).

---

## 5. Risks / Gate-must-verify

- [ ] One `WriteBatch`, one `.commit()` — never a per-doc `awaitServerAck` walk (the round-3 [P1]).
- [ ] Reverse uses each original's STORED amount/eventId/currency — NOT a re-decomposition of the current balance.
- [ ] Idempotency: THREE guards — (a) corrected logical row hides the affordance (regroup `isCorrected`); (b) callback no-ops on re-entry after the stream emits (correction-note presence, step 2); (c) **in-flight `_correctingSettleUpIds` set (step 1+5) covers the double-tap-before-stream-emits window** — this last is the one that actually prevents double-reverse mid-flight; (a)/(b) alone do NOT.
- [ ] `onCorrect: void Function(Settlement)` is UNCHANGED; the event screen is untouched; tagged slices stay uncorrectable on the event screen (by design).
- [ ] Untagged history rows render byte-identical to today (no regroup) — existing `settle_up_correction_test.dart` passes unchanged.
- [ ] Reverse doc shapes pass `validEventSettlementBase`/`validGroupSettlementBase` `hasOnly` (event reverse has NO `scope`/`groupId`; residual reverse HAS `scope=='group'`+`groupId`+`eventId`==groupId).
- [ ] `ledgerRevisionProvider` bumped after the commit (reverses include event settlements → home staleness).
- [ ] No activity log on a correction; one snackbar; one connectivity note.
- [ ] Departed-party-with-residual correction fails atomically (no partial) — relies on the residual rule's `in memberIds`, already emulator-pinned in PR1.
- [ ] CLIENT-ONLY: confirm no rules/schema/Functions diff; no backend deploy in PR2.
- [ ] PR1's `group_settle_up_decompose_test.dart` assertions FLIP — specifically the **correct-button-HIDDEN-on-tagged** test (`group_settle_up_decompose_test.dart:544`, verified by the Gate) now expects a LOGICAL correct button on an uncorrected tagged row, and the **history-union** test (`:505-525`) now expects ONE regrouped row instead of per-doc rows. Update those exact assertions; don't patch around them. (There is no literal "N+1 row-count" assertion to flip — name the real ones.)

## 6. Open questions (resolve in/after the Gate)
- **Q1 (membership pre-gate):** rely on batch atomicity (default, simplest) OR add a pre-gate that hides the logical button when a party departed + a residual exists (UX polish, avoids a surprising error)? Default: atomicity only; surface the error cleanly.
- **Q2 (corrected-row visual):** one regrouped row that flips to "Correction" state (chosen) vs. two rows (original + a "Correction" row, mirroring the untagged single-doc look)? Chosen: one row (the regroup's point is one logical row).
- **Q3 (event-screen slices):** confirmed uncorrectable on the event screen (no `onCorrectLogical` there). The slice still shows in that event's history as a (now-untagged-looking?) row — verify a tagged event slice viewed on the EVENT screen renders sanely (it has `groupSettleUpId != null` but the event screen does NOT regroup; it would show per-doc with the PR1 hide-guard still hiding its single-doc button). Confirm the event screen path is unchanged and acceptable.

## 7. Sequencing (each slice leaves the tree green)
1. `SettlementCorrectionService.reverseLogicalSettleUp` + provider + unit tests (§1). RED→GREEN.
2. `groupSettlementHistory` pure regroup + tests (§2). RED→GREEN.
3. `_PaymentHistorySection`/`_HistoryTile` logical rendering (§2) + widget tests.
4. `onCorrectLogical` callback + `_correctLogicalSettleUp` orchestration + idempotency + tests (§3). RED regression (a decomposed settle-up's correct re-opens the event ledger) → GREEN.
5. Flip PR1's now-stale assertions (§5 last box); `flutter analyze`, `tool/check_theme_purity.sh`, full suite.
6. PR body `Closes #753` (PR2 is the WHOLE of #753) — and put `Closes #753` in the COMMIT message too (squash-merge auto-closes from the commit body). Base the PR on `feat/752-decompose-group-settlements`. `/automerge` (Gate-category → fresh-Opus review).
