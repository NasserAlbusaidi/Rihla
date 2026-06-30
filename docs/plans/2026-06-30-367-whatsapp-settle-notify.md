# #367 — WhatsApp settle-up notify (numberless)

**Date:** 2026-06-30 · **Issue:** #367 · **Epic:** #708 Settle & Seal (sequenced first)
**Gate:** EXEMPT — no money math, no rules, no routing, no schema. Pure string-build + `url_launcher` handoff.
**Design:** signed off on canvas (Rihla Design System → Settle & Seal), Variant A. Mockup `docs/design/mockups/367-settle-notify.html`.

## What done looks like

After a debtor records a settlement **they made** (single-tile path), a follow-up nudge sheet offers to let
the creditor know via WhatsApp. The settlement record is unchanged (append-only, fires first). The nudge:
- shows a preview of the exact prefilled message,
- `[Not now]` dismisses, `[WhatsApp]` opens WhatsApp prefilled (numberless `whatsapp://send?text=`),
- WhatsApp-not-installed → `shareText` OS share-sheet fallback (never a dead end).

Honest **past tense**, **scope-named**:
- event settle → `"Hey {name}, I've sent you {amount} for {event} in {group}."`
- group settle → `"Hey {name}, I've sent you {amount} for {group}."`

Amount = the **live/edited** amount the user just recorded, per-currency decimals (JPY×1), LTR-Latin in Arabic.

## Gating (the load-bearing correctness)

Nudge fires ONLY when ALL hold:
1. **Debtor**: `currentUid == fromUserId` (`RecordPaymentPerspective.paying`). Creditor-records (#282) & settle-on-behalf (#595) → no nudge.
2. **Single-tile**: `stepLabel == null`. The stepped multi-currency walk shows its own aggregate snackbar; no per-step nudge (message carries one amount/currency). v1 scope.
3. **Recorded**: outcome `_StepOutcomeKind.recorded` (not cancelled/invalid/failed).
4. **Not a correction**: the `onCorrect` offset path calls `_recordSettlement` directly, bypassing `_showRecordPaymentSheet` → never reaches the nudge. (No extra guard needed; pinned by a test.)

Attach point = end of `_showRecordPaymentSheet` (both screens), after `_recordSettlement` returns `recorded`.
Guard every post-await UI step with `context.mounted`.

## Files

**New**
- `lib/core/utils/settle_notify.dart` — pure `settleNotifyMessage({l10n, recipientName, amountDisplay, eventName, groupName})`; `eventName==null` ⇒ group template, else event template.
- `lib/features/groups/widgets/settle_notify_sheet.dart` — `Future<bool> showSettleNotifySheet(ctx, {recipientName, message})` (Variant A: ✓ badge, title, message-preview bubble, `[Not now]`/`[WhatsApp]`). Pure-presentational, returns true on WhatsApp tap; caller launches.
- Tests: `test/core/utils/settle_notify_test.dart`, `test/features/groups/settle_notify_sheet_test.dart`, screen-level nudge gating in `test/features/ledger/settle_up_screen_*`/`group_settle_up_*` (reuse existing harness).

**Modify**
- `lib/core/utils/whatsapp_share.dart` — add general `whatsAppTextUri(msg)` + `shareViaWhatsApp(msg, {fallback})`; keep `whatsAppInviteUri`/`shareInviteViaWhatsApp` as thin delegates (zero churn to #354 tests).
- `lib/features/ledger/screens/settle_up_screen.dart` — thread `eventName`+`groupName` into `_showRecordPaymentSheet`; show nudge → launch. Import `whatsapp_share`, `settle_notify`, `settle_notify_sheet`, `share_helper`.
- `lib/features/groups/screens/group_settle_up_screen.dart` — same, `eventName: null`, `groupName: group.name`.
- `lib/l10n/app_en.arb` + `app_ar.arb` — `settleNotifySheetTitle(name)`, `settleNotifySheetBody`, `settleNotifyNotNow`, `settleNotifyWhatsApp`, `settleNotifyMessageEvent(name, amount, event, group)`, `settleNotifyMessageGroup(name, amount, group)`. Amount stays LTR-Latin in `ar`.

## TDD order (RED→GREEN each)

1. `settle_notify_test.dart` — event vs group template selection; amount string placed verbatim. → impl `settle_notify.dart`.
2. `whatsapp_share_test.dart` — `whatsAppTextUri`/`shareViaWhatsApp` parity (general primitives). → impl delegates.
3. `settle_notify_sheet_test.dart` — renders preview text; WhatsApp tap pops `true`, Not-now pops `false`. → impl sheet.
4. Screen gating — debtor single-tile record shows nudge (mock url_launcher, assert sheet key present); creditor/stepped/correction do NOT. → impl wiring in both screens.

## Verification

- `flutter analyze` clean; `bash tool/check_theme_purity.sh` clean (new widget — watch for missing token justifications).
- Targeted: `flutter test test/core/utils/settle_notify_test.dart test/core/utils/whatsapp_share_test.dart test/features/groups/settle_notify_sheet_test.dart` then the two screen tests; then full suite.
- Manual sanity: not required for merge (Gate-exempt) but note RTL + JPY amount in the message.

## Out of scope (explicit)

No IBAN, no QR, no stored numbers, no schema, no rules, no deep-link back into the app (all dropped in the
2026-06-29 reshape). No change to settlement semantics (stays one-sided/append-only). Stepped-walk per-step
nudge deferred. Issue body to be rewritten to this reshaped scope; `decision`/`privacy` labels resolved.
