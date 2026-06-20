# Settle on behalf — any member can record a transfer between two others

**Date:** 2026-06-20
**Status:** spec → implement
**Reporter:** user ("I the creator can't settle money between two people")
**Scope decision (user, 2026-06-20):** **Any group member** can record a suggested
transfer between two other members — not creator-only. Splitwise parity.

## Problem

In Settle-Up, a transfer tile (e.g. "Bob → Alice OMR 7.750") only shows a
**record** button when the current user is the payer (debtor) **or** the recipient
(creditor) of that transfer. A pure third party — including the group
creator/organizer — sees the tile but no button, so they cannot record a payment
that happened between two other people. The organizer who collects and settles on
the group's behalf is blocked.

## Root cause (verified against code)

`SettleUpPageBody._buildTile` (`lib/features/groups/widgets/settle_up_page_body.dart:339`):

```dart
onRecord: (isYourAction || isCreditor) ? () { … onRecord(…) } : null,
```

A third party gets `onRecord: null`. This is the **only** block. Both the
event-level (`settle_up_screen.dart`) and group-level (`group_settle_up_screen.dart`)
screens render the same `SettleUpPageBody`, so the gate lives in one place.

## Server already allows it — client-only change, no deploy

`firestore.rules` `validEventSettlementCreate` (`:707`) /
`validGroupSettlementCreate` (`:905`) require only:
- writer is an event participant / group member,
- `payerParticipantId` & `recipientParticipantId` are participants/members,
- `createdBy == request.auth.uid`.

There is **no** `payerParticipantId == auth.uid` pin. A participant may already
write a settlement between any two other participants. The restriction is purely
client-side UI. → **No rules change, no Functions change, no deploy.** NOT a
Gate-category change (no BalanceCalculator/MoneySerializer/rules/routing/schema
surface; the persisted settlement shape is byte-identical to today's).

### ⚠️ Post-review correction (fresh-context adversarial review, confirmed P2)

The "no payer==auth pin" fact is true but INCOMPLETE for the **event** path:
`validEventSettlementCreate` gates the WRITER on `isEventParticipant` =
`request.auth.uid in event.participantIds` (`isEventParticipant`,
`firestore.rules:152`). `participantIds` is a user-selected SUBSET of group
members. A group member who is NOT an event participant can still READ (and reach)
an event's settle-up (read is `isGroupMember`-gated). With an unconditional
button they'd get a Record affordance that the server `permission-denied`s.

→ Corrected scope:
- **Event screen:** only event **participants** may record (matches the rule).
- **Group screen:** any **member** may record (`validGroupSettlementCreate` needs
  only `isGroupMember`, and every viewer is already a member).

Implemented via `SettleUpPageBody.canRecord` (default `true`): the event screen
passes `currentUid != null && event.participantIds.contains(currentUid)`; the
group screen passes `true`. When `false`, no per-tile Record button and no
stepped card. (Also verified: the group activity feed renders the generic
`activityGroupSettlementDescription` = "recorded a settlement" — the raw
`description` string is never displayed, so a third-party recorder is shown as
"<Carol> recorded a settlement", which is accurate.)

## The framing problem

`record_payment_sheet.dart` has two framings via `bool isReceiving`:
- `false` (you're the payer): "Mark this paid?" / "This records your payment to {to}." / "Mark paid"
- `true`  (you're the recipient): "Mark this received?" / "This records {from}'s payment to you." / "Mark received"

For a third party neither applies — `isReceiving` would be `false`, mis-framing it
as "your payment". Need a neutral third framing: "Record this payment?" /
"This records {from}'s payment to {to} immediately." / "Record".

## Changes (file by file)

1. **`record_payment_sheet.dart`** — replace `bool isReceiving` with
   `enum RecordPaymentPerspective { paying, receiving, recording }` (default
   `paying`). Switch the 3 copy sites (title / banner / button) on it. `recording`
   uses the new neutral strings.

2. **`settle_up_page_body.dart`** (`_buildTile`) — drop the `isYourAction ||
   isCreditor` guard; always wire `onRecord`. The asserts stay. `isYourAction` /
   `isCreditor` still feed tile color / subtitle / label (unchanged).

3. **`group_settlement_tile.dart`** (`_recordLabel`) — add the third-party branch:
   ```dart
   if (widget.isYourAction) return settleUpMarkPaid;     // debtor
   if (widget.isCreditor)   return settleUpMarkReceived; // creditor
   return settleUpRecordPayment;                         // third party → "Record"
   ```
   (Cases are mutually exclusive: one transfer has one payer + one recipient.)

4. **`settle_up_screen.dart` + `group_settle_up_screen.dart`** (`_showRecordPaymentSheet`)
   — replace `isReceiving = currentUid == toUserId` with:
   ```dart
   final perspective = currentUid == fromUserId
       ? RecordPaymentPerspective.paying
       : currentUid == toUserId
           ? RecordPaymentPerspective.receiving
           : RecordPaymentPerspective.recording;
   ```

5. **l10n** (`app_en.arb` + `app_ar.arb`) — 3 new strings:
   - `settleUpRecordThisTitle` = "Record this payment?"
   - `settleUpRecordsForOthersImmediately(fromName, toName)` = "This records {fromName}'s payment to {toName} immediately."
   - `settleUpRecordPayment` = "Record"

6. **`generated_l10n_surface_test.dart`** — register the 3 new getters.

## Non-goals (intentional)

- **Stepped "settle all with X" card stays me-relative.** `steppedSettlePairs`
  filters `involvesMe`; a third party gets per-tile record buttons only, never a
  stepped card ("with X" framing is only meaningful when X is *my* counterparty).
- **No creator-only gating** (user chose any-member).
- **#283 correction path unchanged** — `onCorrect` records the offset directly,
  not through `_showRecordPaymentSheet`, so perspective never applies there.

## 7 verification principles

1. **Callsite classification.** New `perspective` enum is **INBOUND** (display copy
   only, never persisted). `fromRawName`/`toRawName` remain **OUTBOUND**
   (persisted payerName/recipientName) — unchanged. `createdBy` = writer uid
   (OUTBOUND) — unchanged, already correct. No new OUTBOUND field; only a new set
   of *writers*.
2. **Concrete claims re-checked.** Rule line numbers, `onRecord: null` gate,
   `isReceiving` callers (2 screens + sheet + 1 test) all grepped live above.
3. **Read-path per write-path.** A third-party settlement is read by
   `BalanceCalculator.calculateBalances` (folds payer→recipient net — direction,
   not creator) and the payment-history footer (already renders arbitrary
   payer/recipient). Home aggregate: **event** settlements need the
   `ledgerRevisionProvider` bump — `settle_up_screen._recordSettlement` already
   bumps it (`:541`); **group** settlements are live-watched (no bump). No
   staleness regression.
4. **Fields from the type.** Settlement shape unchanged — no field added/renamed.
5. **Data contracts.** `onRecord` callback signature unchanged. Sheet param swaps
   `isReceiving: bool` → `perspective: RecordPaymentPerspective` (default `paying`,
   so any unmigrated caller is byte-identical to old `isReceiving:false`).
6. **Arithmetic.** No allocator / decomposition change. A third-party-recorded
   settlement reduces the debtor→creditor edge identically regardless of writer.
7. **Adversarial orthogonal axis.** Fix is on the **identity** axis (who may
   write). Worked example exercises **money-flow + identity together**: a third
   party (Carol, currentUid='carol') records the optimal Bob→Alice transfer; the
   persisted doc must be `payer=bob, recipient=alice, createdBy=carol` (direction
   follows the transfer, not who tapped), and the creditor "Mark received" path
   must stay green (don't regress #282).

## Tests (RED first)

- **`settle_up_screen_test.dart`** (event, identity+money): `currentUid:'carol'`
  (third party; participants are alice/bob). Assert `settleUpRecordPaymentButton`
  visible; tap → markAsPaid → persisted settlement `payer=bob, recipient=alice,
  createdBy=carol`. RED today (button is `null` for a third party → button absent).
- **`record_payment_sheet_test.dart`** (framing): `perspective: recording` renders
  "Record this payment?" + "…payment to …" neutral banner + "Record" button. Update
  the existing `isReceiving:true` test → `perspective: receiving`.
- Keep green: debtor "Mark paid", creditor "Mark received" (#282), stepped walk.

## Verify

`flutter analyze` clean; `flutter test` for the touched suites
(`test/features/ledger/`, `test/features/groups/`, `test/unit/generated_l10n_surface_test.dart`)
+ full suite. Then a fresh-context adversarial review (Workflow) before finishing.
