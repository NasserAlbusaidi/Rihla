# #682 — Offline event-settings Save: distinct queued feedback

## Problem (verified against code, not the issue's prose)

The issue claims the Save spinner "hangs" offline. **It does not.** `awaitServerAck`
(`lib/core/utils/write_ack.dart`) already races the write against
`kWriteAckTimeout = 5s` and returns `WriteAck.queued` on timeout. The actual defect,
confirmed by the v1.6.2 QA evidence (Pixel screenshots at `0.7s / 3.7s / 8.7s`):

1. When the connectivity probe is **stale** (reads `online` but the device is offline —
   the probe lags reality up to 60s, #633), `skipWait` is false, so Save shows a ~5s
   spinner before resolving to queued.
2. On the queued outcome, `EventInfoSection._save` shows the **same** generic
   `eventUpdated` ("Event updated") snackbar it shows on a real server ack — 2s, no
   "will sync" wording. By 8.7s it has auto-dismissed → the user sees the edit form with
   no confirmation and is "unsure whether Save worked."

Event-settings is the **only** queued write site without distinct offline feedback.
`add_expense`, `edit_expense`, `settle_up`, create-group, create-event all branch on
`WriteAck.acked` and surface a "— will sync when online." message (l10n keys
`eventCreatedWillSync`, `groupCreatedWillSync`, `settleUpRecordedWillSync` already exist).

## Fix (one concern: bring event-settings in line with every other write site)

1. Add `eventUpdatedWillSync` l10n key — EN "Event updated — will sync when online.",
   AR mirror of `eventCreatedWillSync`.
2. `EventInfoSection._save`: when `outcome == WriteAck.queued`, show `eventUpdatedWillSync`
   with a longer 4s dwell (clearer, harder to miss); acked keeps `eventUpdated` @ 2s.

## Explicitly out of scope

- **Not** touching `kWriteAckTimeout`. The 5s spinner is shared by all 5 write sites and
  rooted in the stale-probe window (#633). Shortening it here would (a) break one-PR-one-
  thing, (b) diverge from the other 4 sites, (c) risk false "will sync" on slow-but-online
  networks. Tracked separately under #633.

## Classification / Gate

Not Gate-category: no money math, no `firestore.rules`, no Cloud Functions, no routing, no
schema/field-name change. Display-feedback only. → skip the Gate.

## Read-path classification (verification principle #1)

The only shared surface touched is the snackbar copy in one widget. `outcome` is consumed
INBOUND (display) only. `connectivity.noteQueuedWrite()` already fires unchanged. No write
path altered.

## TDD

- RED (new): `event_settings_offline_412_test.dart` — connectivity reads `online` (stale
  probe), `updateEvent` returns a never-completing `Completer` (truly offline), tap Save,
  pump past `kWriteAckTimeout`. Assert the **will-sync** copy + spinner released + syncing.
  Fails on current code (shows "Event updated").
- Update existing #667 clean-offline test: its queued outcome now shows the will-sync copy.
- Online-acked path (`event_settings_screen_test.dart:686`) unchanged — keeps "Event updated".

## Files

- `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ `flutter gen-l10n`)
- `lib/features/events/widgets/event_info_section.dart`
- `test/features/events/event_settings_offline_412_test.dart`
