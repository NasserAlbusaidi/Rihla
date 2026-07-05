# Rihla v1.7.4 First Track QA

Date: 2026-07-05 09:39 +04  
Device: Pixel 9 Pro XL, Android 16, installed from Google Play first track  
Build under test: `com.safar.safar` `versionName=1.7.4`, `versionCode=32`

## Scope

Single-device Play-installed QA sweep for user-facing work shipped since public
`1.7.0`. This was a non-mutating pass: screens were opened, filters/search were
used, external PayPal handoff was tested, and editor/review sheets were
exercised, but no new expense, settlement, group, or event was saved.

Evidence folder:
`docs/qa-evidence/v1.7.4-first-track-2026-07-05/`

Backend/release checks:

- `tool/pending_deploy.sh`: production backend is up to date.
- Installed app: `versionName=1.7.4`, `versionCode=32`, installer
  `com.android.vending`.
- Release workflow: v1.7.4 Android release workflow completed successfully.

## Release Call

Not clean for public production yet.

The first-track build is mechanically installed and the backend is current, but
two user-visible issues should be fixed before widening public release:

1. PayPal support CTA opens a donation page that PayPal rejects for the
   configured country.
2. Pre-settlement review fires for already-settled suspicious expenses, creating
   a false warning on settle-up entry.

The hard-coded OMR/AED currency explainer is also a small copy fix that should
ship with the same patch if possible.

## Passes

| Area | Result | Evidence |
| --- | --- | --- |
| Home / active journeys | Home renders balance hero, active journeys, recently viewed, group list, and persistent Add Expense FAB. | `01-foreground.*`, `20-home-groups-list.*` |
| History / activity unification | History tab renders grouped activity, filters, search field, and expense-row deep link into the event ledger. | `02-history-tab.*`, `03-history-search-open.*`, `04-history-search-fatma.*`, `05-history-expenses-filter.*`, `06-history-expense-row-deeplink.*` |
| Event command screen | Event hub opens with recap banner, Expenses / Settle up / Activity tabs, embedded ledger, and activity feed. | `07-group-detail.*`, `08-event-hub-activity-tab.*`, `19-group-or-event-from-card.*` |
| Group detail / insights | Group screen renders balance, events, people, and spending summary insights. | `21-group-detail-home.*` |
| Group activity | Group activity screen renders scoped filters and mixed activity rows. | `22-group-activity.*` |
| Add Expense editor | Editor opens, shows category requirement marker, currency mismatch note, split modes, exact split editor, and itemized editor. | `11-add-expense-start.*`, `13-add-expense-exact-mode.*`, `14-add-expense-itemized-mode.*` |
| Global Add Expense FAB | FAB opens flattened event picker with open events and browse-all-groups entry. | `25-global-add-expense-picker.*`, `26-final-dismissed-picker.png` |
| Profile / account state | Profile shows backed-up account state, Google identity state, support/legal/about area, and v1.7.4 footer. | `15-profile.*`, `16-profile-support-area.*` |
| Settle-up calculation after review | After bypassing review, settle-up rendered the current actionable settlement bucket. | `10-event-settle-up-after-review.*`, `24-group-settle-up-after-review.*` |

## Findings

### F1 - PayPal support CTA cannot complete

Severity: High for public release polish / trust.
GitHub: https://github.com/NasserAlbusaidi/Rihla/issues/897

The Profile "Buy me a coffee" tile launches Chrome successfully, but PayPal
rejects the donation page with: `Donations aren't supported in this organization's country`.

Evidence:

- `16-profile-support-area.*`: support tile is visible.
- `17-paypal-handoff.*`: PayPal rejection page after tapping the tile.

Code path:

- `lib/core/config/app_links.dart:25-29` defines `AppLinks.paypalUrl`.
- `lib/features/settings/widgets/profile_support_section.dart:59-75` launches
  that URL externally.

Recommended fix:

Hide the coffee tile or replace it with a supported support/payment channel
before public release. The launch itself succeeds, so the app currently treats
this as success even though the destination rejects the flow.

### F2 - Pre-settlement review triggers on already-settled expenses

Severity: High for settle-up trust.
GitHub: https://github.com/NasserAlbusaidi/Rihla/issues/898

Both event-level and group-level settle-up showed the pre-settlement review
sheet for a large/exact expense even though that suspicious OMR amount was
already settled. After continuing past the sheet, the event settle-up showed
`OMR 0.000 total`; the group settle-up showed the remaining actionable target
in a different currency.

Evidence:

- `09-event-hub-settle-up-tab.*`: review sheet flags large/exact OMR expenses.
- `10-event-settle-up-after-review.*`: after continuing, OMR is already zero.
- `23-group-settle-up-entry.*`: group settle-up repeats the same review.
- `24-group-settle-up-after-review.*`: actual remaining target is USD.

Code path:

- `lib/features/ledger/services/pre_settlement_review.dart:44-85` detects flags
  from live expenses only.
- `lib/features/ledger/screens/settle_up_screen.dart:227-240` calls the detector
  before balances/settlements are used to build settle-up buckets.
- `lib/features/groups/providers/group_presettle_review_provider.dart:52-69`
  unions per-event expense flags for group settle-up.
- `test/features/groups/group_settle_up_review_sheet_test.dart:90-124` currently
  pins the old behavior: the sheet trigger is independent of net amounts.

Recommended fix:

Make the review trigger settlement-aware. At minimum, suppress flags for
currency buckets with no outstanding optimal settlement. Better: filter
review-worthy expenses to rows that still contribute to a non-zero outstanding
balance, then update the group/event tests to assert already-settled suspicious
expenses do not trigger the sheet.

### F3 - Currency explainer hard-codes OMR/AED

Severity: Medium / easy patch.
GitHub: https://github.com/NasserAlbusaidi/Rihla/issues/899

In mixed OMR/USD contexts, the settle-up explainer still says
`OMR can't cancel out AED`.

Evidence:

- `10-event-settle-up-after-review.*`
- `24-group-settle-up-after-review.*`

Code path:

- `lib/l10n/app_en.arb:1202-1208`
- `lib/features/groups/widgets/currency_buckets_explainer.dart` documents the
  same fixed example.

Recommended fix:

Use generic copy, e.g. `Different currencies cannot cancel each other out`, or
interpolate the active bucket currencies.

## Not Fully Covered

The following release areas still need a separate QA pass because they require a
second device, production writes, push delivery, offline toggling, or export
handoffs:

- True two-device sync/conflict QA.
- Offline create/replay and stale amount revalidation with network toggles.
- Push notification delivery/copy.
- Recording a settlement and WhatsApp settle notification.
- Trip receipt proof pack/export/share flow.
- Weighted-split zero-share write behavior.
- Account deletion/recovery destructive flows.
