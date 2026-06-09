# #282 — Let the creditor record a payment received

**Issue:** A "Mark paid" button renders only for the debtor (`fromUserId == currentUid`).
A lender (creditor) can't log "Ahmed paid me back in cash" — they must wait for the
(possibly disengaged, anonymous) debtor. In a cash economy this leaves real debts
permanently unsettled. Fix: let the creditor record a received payment too, keeping
the append-only settlement model.

## Gate classification: NOT Gate-category (verified against code)

- **Write path unchanged.** Both `_recordSettlement` already pass the *settlement's*
  `fromUserId`/`toUserId` as `payerParticipantId`/`recipientParticipantId` (not
  `currentUid`); only `createdBy` is the actor. Enabling the creditor's button records
  payer=debtor, recipient=creditor, createdBy=creditor — money-correct, no calc change.
- **Rules already permit it.** `firestore.rules` settlement-create
  (`validEventSettlementCreate` :734, `validGroupSettlement*` create, base :704-732)
  require only `createdBy == request.auth.uid` + payer/recipient ∈ participants. There is
  **no `payerParticipantId == request.auth.uid` pin** — a creditor (a participant)
  creating with payer=debtor passes as-is. No rules change.
- No schema/field change, no routing change. → Gate skipped per contract (outside all
  Gate categories). TDD still applies (money-adjacent feature: red-green).

## Changes

1. `settle_up_page_body.dart` — gate `onRecord` on `isYourAction || isCreditor` (was
   `isYourAction` only). A pure third party (neither party) still gets no button.
2. `group_settlement_tile.dart` — record-button label: `settleUpMarkReceived`
   ("Mark received") when `isCreditor && !isYourAction`, else `settleUpMarkPaid`.
3. `record_payment_sheet.dart` — add optional `bool isReceiving = false`. When true:
   title → `settleUpMarkThisReceivedTitle`; banner → `settleUpRecordsReceivedImmediately`
   (passes the *payer's* name); confirm button → `settleUpMarkReceived`. Body and payee
   card ("X pays Y") stay — factually correct from either side.
4. `settle_up_screen.dart` (event) — pass `isReceiving = currentUserIdProvider == toUserId`
   to the sheet.
5. `group_settle_up_screen.dart` — pass `isReceiving` to the sheet; **fix the activity-log
   description counterparty** (`:420` hardcodes `toName`, wrong when the creditor is the
   actor) → counterparty relative to the actor.
6. l10n: add `settleUpMarkReceived`, `settleUpMarkThisReceivedTitle`,
   `settleUpRecordsReceivedImmediately` to `app_en.arb` + `app_ar.arb`.

## Testing note (the #390/#392 pitfall)

- Event screen: `createdBy` = `ref.read(currentUserIdProvider)` → testable. The
  actor-as-creditor money assertion (payer=debtor, recipient=creditor, createdBy=creditor)
  lives here.
- Group screen: `createdBy` = `FirebaseConfig.currentUser?.uid` (throws `[core/no-app]`
  in unit tests → falls back to `fromUserId`). So the group test asserts payer/recipient
  *direction* + "Mark received" visibility, not the actor uid (prod-correct via the rules'
  `createdBy == auth.uid`). Button gating + sheet framing use `currentUserIdProvider`
  (overridable), so they ARE testable on both screens.

## RED → GREEN

- Group: creditor (`uid-alice`) sees `settleUpRecordPaymentButton` (was findsNothing).
- Group: creditor records → payer=`uid-bob`, recipient=`uid-alice`.
- Event: creditor (`alice`) records → payer=`bob`, recipient=`alice`, createdBy=`alice`.
- Sheet: `isReceiving:true` → received title + "Mark received" button + payer-named banner.
