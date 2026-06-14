# Spec — #283 discoverable settlement correction (offsetting entry, append-only)

**Date:** 2026-06-14 · **Issue:** #283 · **Gate:** required (money/integrity — settlement write, alters displayed settle-up/balance numbers)

## Problem
Settlements are append-only by design (B3 / KEEP-list #149; `settlement_service.dart` + `group_settlement_service.dart` have no delete/update; `firestore.rules` denies settlement update/delete). The payment-history tile (`_HistoryTile` in `settle_up_page_body.dart:647`) is fully inert except a share button — a user who records the wrong amount/person has no discoverable way to fix it and won't intuit "record a reverse payment."

## Fix (exact scope)
Add a **"correct this"** affordance to each `_HistoryTile` that, after a confirmation dialog, records an **offsetting reverse settlement** through the **existing** write path for that settlement's scope. Explicitly NOT a delete/edit — the original row stays; a new reversing row nets it out. No schema change, no `firestore.rules` change, no new service method.

### The offsetting settlement
For an original settlement `S` (payer `P`, recipient `R`, amount `A`, currency `C`):
- new settlement: payer = `R`, recipient = `P`, amount = `A` (unchanged, positive), currency = `C` (unchanged), `createdBy` = current uid, `note` = localized correction note, names swapped (`payerName = S.recipientName`, `recipientName = S.payerName`).

This exactly cancels `S` in `calculateBalances`. **Direction verified (Gate R1):** `expense_provider.dart` folds a settlement as payer `+amount`, recipient `−amount` into net; so `P→R A` then `R→P A` nets each party to zero (cancels, does NOT double). Currency is preserved so it lands in the same per-currency bucket (no cross-currency netting — #382).

### Implementation = reuse each screen's existing `_recordSettlement` (Gate R1 P1-1/P1-2/P2-3/P2-5)
The swap is NOT hand-built and there is NO scope-dispatch. Each screen's history stream is **scope-homogeneous** (event screen shows only event settlements via `eventSettlementsProvider`; group screen only group settlements via `groupSettlementsProvider`), so the correction simply calls **that screen's own `_recordSettlement`** with swapped from/to. That method already: resolves the actor uid (each screen its own way — event `currentUserIdProvider`, group `FirebaseConfig.currentUser?.uid`), races `awaitServerAck`, applies `#104`/`#357`/`#412` effects, shows the success snackbar, and — critically — **wraps the write in try/catch → `settlementWriteErrorMessage(classifySettlementWriteError(e))` error snackbar.** So a departed-party offset (rules reject `payerParticipantId in participants()`/`memberIds` when a party has left — #249) surfaces a clear error, never a silent failure or bad data.

## Data contracts (exact)

`SettleUpPageBody` gains one **optional** callback (unlike the **required** `onRecord` at `settle_up_page_body.dart:179`); null hides the affordance, keeping existing call sites/tests valid:
```dart
final void Function(Settlement settlement)? onCorrect;
```
Threaded through all three widgets: `SettleUpPageBody` → `_PaymentHistorySection` (constructor gains `onCorrect`, currently takes `settlements/displayNames/subjectName`) → `_HistoryTile(onCorrect:)`.

`_HistoryTile`: a new `IconButton` (icon `Iconsax.undo` / reverse) beside the share button, shown **only when `onCorrect != null` AND both `settlement.payerParticipantId` and `settlement.recipientParticipantId` are non-null/non-empty** (a correction needs both party ids to target; legacy id-less rows show no affordance). `tooltip = l10n.settleUpCorrect`, keyed `GroupKeys.settleUpCorrectButton` on `index == 0` only (mirrors share-button keying for a predictable widget-test target). `onPressed` → `_confirmAndCorrect(context)`:
1. `showDialog` (AlertDialog): title `settleUpCorrectTitle`, content `settleUpCorrectBody(recipientName, payerName, amountStr)` — **reuses the tile's already-resolved `payerName`/`recipientName` locals** (the `displayNames[id] ?? settlement.x ?? Unknown` fallback chain), NOT a fresh lookup. Describes the REVERSE flow: "{recipient} pays {payer} back {amount}". Actions: Cancel (`commonCancel`) + Confirm (`settleUpCorrectConfirm`).
2. On confirm → `onCorrect!(settlement)`.

### Screen handlers (reuse `_recordSettlement`, swapped)
- **`settle_up_screen.dart`** (event): `onCorrect: (s) => _recordSettlement(context, fromUserId: s.recipientParticipantId!, toUserId: s.payerParticipantId!, fromName: s.recipientName ?? '', toName: s.payerName ?? '', amount: s.amount, currency: s.currency, note: context.l10n.settleUpCorrectionNote)`. The `!` is safe — the affordance is hidden unless both ids are non-null (above). Inherits event `_recordSettlement`'s `widget.eventId`, `ledgerRevision++`, connectivity, snackbars, error path. (Event path has no activity log.)
- **`group_settle_up_screen.dart`** (group): add a `bool logActivity = true` param to its `_recordSettlement`; the suggestion-tile path keeps the default (logs `group_settlement`). The correction calls `_recordSettlement(context, group: group, fromUserId: s.recipientParticipantId!, toUserId: s.payerParticipantId!, fromName: s.recipientName ?? '', toName: s.payerName ?? '', amount: s.amount, currency: s.currency, note: l10n.settleUpCorrectionNote, logActivity: false)`. `logActivity: false` suppresses the `logGroupEvent('group_settlement', "settled X with Y")` call — a reversal must not appear in the type-rendered activity feed as a fresh payment (Gate R1 P2-5). Consistent with the event path (no activity log). The correction stays fully auditable via settlement history + balances.

## Verification principles (run inline)
1. **Callsite classification.** `onCorrect` is OUTBOUND (feeds a settlement write). The swapped fields are persisted. Verified the swap is correct: original P→R, offset R→P, same A/C. No display-formatted string reaches the write (amount stays `Decimal` → `MoneySerializer.toSubunits`; names are the persisted `payerName`/`recipientName`, not formatted).
2. **Concrete claims vs code.** `addSettlement`/`addGroupSettlement` signatures verified (`settlement_service.dart:71`, `group_settlement_service.dart:55`). `Settlement.scope`/`tripId`/`payerParticipantId`/`recipientParticipantId`/`payerName`/`recipientName`/`amount`/`currency` verified (`settlement_model.dart`). Route/keys: `GroupKeys` to gain `settleUpCorrectButton`.
3. **Read-path per write-path.** The offset settlement is read by: `watchSettlements`/`watchGroupSettlements` (history stream → shows the new reversing row), and `calculateBalances` (nets it). Named consumers exist; no new reader needed.
4. **Fields from the type.** `addSettlement` sets: id, eventId, payer/recipientParticipantId, payer/recipientName, amountFils, currency, note, isDeleted=false, deletedAt=null, settledAt=now, createdBy. `addGroupSettlement` additionally sets groupId, eventId=groupId sentinel, scope='group'. The correction passes the SAME inputs the service already requires — nothing omitted.
5. **Data contract at the seam.** `onCorrect(Settlement)` — exact type. Screen reads `s.recipientParticipantId`→`fromUserId`, `s.payerParticipantId`→`toUserId` (the swap), `s.recipientName`/`s.payerName` (→ `fromName`/`toName`, `?? ''`), `s.amount`, `s.currency`. NOT `s.scope`/`s.tripId` (no dispatch — each screen uses its own ids). Ids are non-null because the affordance is gated on both ids present.
6. **Arithmetic decomposition.** Correction does not touch aggregation; it appends one settlement. `netBalance` folds settlements, so original + offset ⇒ +A then −A on the same pair ⇒ net 0. `totalPaid` does NOT fold settlements (irrelevant here — corrections are settlements, not expenses). No aggregate field is reconstructed.
7. **Adversarial pass (orthogonal axis — multi-currency + identity).** A 2-currency event: a USD settlement's offset must be USD (same bucket), an OMR settlement's offset OMR — verified by passing `currency: s.currency`. Identity: swapped ids must be the original parties (both in the balance universe) — a wrong-direction offset (same direction, not swapped) would DOUBLE the debt, not cancel it → the money test (below) pins direction by asserting net-zero.

## Tests (RED first)
- **A — widget (`settle_up_page_body` test):** a history tile renders the correct affordance (`GroupKeys.settleUpCorrectButton`); tapping → confirm dialog visible; tapping Confirm → `onCorrect` called once with that `Settlement`. RED: no correct button today.
- **B — money/direction (unit, `FakeFirebaseFirestore`):** record `P→R A` via `addSettlement`; then record the offset `R→P A`; assert `calculateBalances` nets both parties to zero for that event (proves the correction direction cancels, not doubles). RED before the handler swap logic exists / GREEN after. (Direction is the load-bearing money fact; a same-direction bug doubles debt and this test catches it.)
- Existing settle-up widget tests stay green (affordance is additive; `onCorrect` optional).

## Out of scope (explicit)
- No `correctionOf`/`reversalOf` linking field (issue says plain offsetting entry; B3).
- No delete/edit of the original.
- No restriction on who may correct beyond existing settlement-write auth (the rules already gate creates on party/membership; the confirm dialog guards accidental taps). Mirrors open-edit philosophy.
- **Departed-party affordance gating deferred (Gate R1 P1-2):** correcting a settlement whose counterparty has LEFT the event/group fails the rules `participantId in participants()`/`memberIds` check → **online** this is handled by the existing `_recordSettlement` try/catch (`classifySettlementWriteError`→`denied`→error snackbar, no crash/bad data). **Offline** (Gate R2 P2): the SDK queues the write optimistically, shows the "will sync" snackbar, and the rules rejection only fires on server replay — silently dropped, no snackbar (pre-existing `#412` behavior of ALL settlement writes; the server refuses it so no bad data persists, but no error is surfaced offline). Proactively hiding the affordance per live-membership needs the live participant set in the tile (not reliably available from `displayNames`) — deferred.
- No change to `firestore.rules`, `functions/**`, models, `money_serializer`, or the activity-feed types/rendering.
- Success snackbar reuses the generic `settleUpRecorded` ("Settlement recorded.") — the confirm dialog already framed it as a correction; a correction-specific success string is not added (scope).

## Acceptance
- [ ] `_HistoryTile` shows a discoverable correct affordance (both event + group settle-up), gated on both party ids present + `onCorrect != null`.
- [ ] Confirm dialog describes the reverse flow ("{recipient} pays {payer} back {amount}") + that the original stays.
- [ ] Confirming records an offsetting settlement via the screen's own `_recordSettlement` (event → `addSettlement`/`widget.eventId`; group → `addGroupSettlement`/`widget.groupId`, `logActivity: false`), swapped parties, same amount + currency, `createdBy` = current uid, correction note.
- [ ] Group correction does NOT emit a `group_settlement` activity entry.
- [ ] Balance nets to zero after correcting a settlement (test B).
- [ ] Departed-party correction surfaces the existing settlement-write error snackbar (no crash, no bad data).
- [ ] EN + AR l10n for all new strings (`settleUpCorrect`, `settleUpCorrectTitle`, `settleUpCorrectBody`, `settleUpCorrectConfirm`, `settleUpCorrectionNote`).
- [ ] `flutter analyze` clean; settle-up + new tests green.
