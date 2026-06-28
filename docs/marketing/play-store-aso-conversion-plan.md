# Rihla Play Store ASO Conversion Plan

Date: 2026-06-27

Goal: turn the current Play listing and SEO pages into a measured acquisition
loop for the first 100 real users. This plan is not a substitute for direct
champion outreach; it keeps the store and search surfaces ready when a champion
or invitee taps a link.

## Current Baseline

| Surface | Current state | First-100 implication |
|---|---|---|
| English title | `Rihla: Split Bills & Settle Up` | Uses the category terms people already understand. |
| English short description | `Split group bills, see who owes who, settle up offline - no signup.` | Strong local conversion promise; keep under the Play short-description limit. |
| English full description | Leads with Oman/Gulf, friend groups, WhatsApp, no signup, and offline use. | Good enough for warm traffic; optimize only with Play Console evidence. |
| Arabic listing | Localized title, short description, full description, and screenshots. | Essential for Oman/GCC trust; keep Arabic copy human, not literal translation. |
| Screenshots | Four English and four Arabic phone screenshots. | Enough to ship; next improvement should make the first two frames show the core loop. |
| Website SEO | English, Arabic, Oman split-bills pages, sitemap, robots, `hreflang`, and Play CTAs. | Supports trust and invite conversion; not the main source of the first 100. |
| First-100 tracker | `docs/marketing/first-100-cohort-tracker.csv` has 40 segment slots and no real names yet. | Do not optimize store copy before named outreach starts. |

## Official Guidance Applied

| Source | Rihla decision |
|---|---|
| Google Play preview assets: https://support.google.com/googleplay/android-developer/answer/9866151 | Keep title, short description, full description, icon, feature graphic, and screenshots clear, accurate, localized, and compliant. |
| Google Play store listing experiments: https://play.google.com/console/about/store-listing-experiments/ | Use experiments only when the listing has enough visitors to produce signal. |
| Google Play custom store listings: https://support.google.com/googleplay/android-developer/answer/9867158 | Prepare custom listings for Oman/GCC travel, dinner, roommate, and Arabic traffic after the first warm cohorts prove which segment converts. |
| Google Search Central SEO starter guide: https://developers.google.com/search/docs/fundamentals/seo-starter-guide | Make each public page descriptive, useful, crawlable, and aligned with real search intent. |
| Google Search localized versions guidance: https://developers.google.com/search/docs/specialty/international/localized-versions | Maintain reciprocal English/Arabic alternates and sitemap `hreflang` entries as pages expand. |

## Do This Before Any Store Experiment

1. Fill at least 10 real champion rows in `first-100-cohort-tracker.csv`.
2. Confirm those champions installed from the public Play listing. The tracker's
   `tester_added` column now means "confirmed installed from Play" (the column
   name stays because the Dart tools depend on it).
3. Send the launch-packet messages from `tool/first_100_launch_packet.dart`.
4. Confirm the listing has at least 100 Store listing visitors or 30 first-time
   installer attempts in Play Console.
5. Create the private Play acquisition log template:
   `dart tool/play_acquisition_summary.dart --write-template="$HOME/Desktop/rihla-play-acquisition-log.csv"`.
6. Record the current baseline:
   - Store listing visitors
   - First-time installers
   - Store listing conversion rate
   - Country/region
   - Language
   - Search terms, when available
   - Install source or campaign/referrer where available

Do not start a Play experiment before the visitor floor is met. A tiny early
sample will produce noise and can slow down the real work: contacting champions
and getting them to create groups.

## Weekly Measurement Loop

Run this once per week while you are still chasing the first 100 users:

1. Run `dart tool/first_100_summary.dart --today=YYYY-MM-DD`.
2. Export or manually record Play Console metrics for the same date range.
3. Add one row to the private Play acquisition log.
4. Run:
   `dart tool/play_acquisition_summary.dart "$HOME/Desktop/rihla-play-acquisition-log.csv" docs/marketing/first-100-cohort-tracker.csv`.
5. Change only one store variable at a time.
6. Leave each tested variant live for at least 7 days or until it has enough
   visitors to compare fairly.
7. Keep the winner only if it improves first-time installers without hurting
   activation in the tracker.

| Week | Date range | Store listing visitors | First-time installers | Conversion rate | Tracker installs | Activated groups | Variant | Decision |
|---|---|---:|---:|---:|---:|---:|---|---|
| 1 |  |  |  |  |  |  | Current listing |  |
| 2 |  |  |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |  |  |

## Experiment Backlog

Run these in order. Do not run multiple experiments at once.

### Experiment 1: Short Description

Hypothesis: invitees convert better when the short description emphasizes the
group-action loop instead of only category terms.

Variant A: current local wedge

```text
Split group bills, see who owes who, settle up offline - no signup.
```

Variant B: invite-first group wedge

```text
Create a group, invite friends, split bills, and settle up clearly.
```

Success metric: higher first-time installer rate from Store listing visitors,
with no drop in `Installed -> group created` in the first-100 tracker.

### Experiment 2: First Two Screenshots

Hypothesis: the first two preview frames should show the full promise without
requiring users to read the full description.

Variant A: current screenshots.

Variant B:

1. Group invite / WhatsApp join moment.
2. Ledger showing who paid and who owes who.
3. Settle-up recommendation.
4. Arabic/English or offline trust frame.

Success metric: higher Store listing conversion rate for warm traffic and no
increase in "installed but did not create/join group" notes.

### Experiment 3: Custom Store Listing For Oman/GCC

Create only after the first 20 champion asks have produced enough signal to
choose a segment.

Recommended custom listings:

| Listing | Audience | Lead promise | Primary screenshot frame |
|---|---|---|---|
| `om-travel-en` | English travel and weekend groups | Split Salalah, camping, and weekend trip costs with your crew. | Trip/event ledger with OMR examples. |
| `om-majlis-ar` | Arabic dinner and gathering groups | قسّم مصاريف العشاء والجمعات واعرف من يدين لمن. | Arabic ledger plus settle-up. |
| `om-roommates-en` | Shared housing and roommate groups | Keep one group for groceries, utilities, and repeat bills. | Persistent group with repeated expenses. |

Success metric: custom listing installs convert to activated groups at least as
well as the main listing. If custom listing installs are lower quality, revert.

### Experiment 4: SEO Page Expansion

Only add pages after the first tracker data shows real demand. Each new page
must answer one actual use case, include English/Arabic alternates when useful,
and appear in `hosting/sitemap.xml`.

Candidate pages:

| Page | Intent |
|---|---|
| `/split-trip-expenses-oman` | Travel crews splitting fuel, stays, food, and activities. |
| `/roommate-bills-oman` | Shared housing groceries, utilities, and rent extras. |
| `/ar/تقسيم-مصاريف-الرحلات` | Arabic travel-expense intent. |

Do not create thin pages just to repeat terms. Each page should be useful enough
to send directly to a champion.

## Metadata Guardrails

- Title: keep at or under 30 characters per locale.
- Short description: keep at or under 80 characters per locale.
- Full description: keep at or under 4,000 characters per locale.
- First 450 characters should explain who the app is for, the job it does, and
  why it is low-friction.
- Keep `No signup required` accurate: optional recovery email exists, but email
  is not required to start.
- Keep offline wording accurate: Firestore offline persistence supports offline
  reads and queued writes; do not imply multi-device conflict-free realtime sync
  while offline.
- Only reference public reviews once the listing actually has them.

## Operator Checklist

Use this before pushing any Play listing update:

1. Run `flutter test --reporter compact test/unit/play_store_metadata_test.dart test/unit/marketing_docs_test.dart test/unit/play_acquisition_summary_test.dart`.
2. Check title, short description, and full description lengths.
3. Confirm screenshots match the claims in the first two description paragraphs.
4. Confirm Arabic and English listings make the same promise.
5. Run `tool/play_acquisition_summary.dart` against the private weekly log and
   confirm the experiment gate is open.
6. Update `first-100-command-center.md` only if the next operating decision
   changes.

## Decision Rule

For the first 100 users, a store change only wins if it improves both:

- Play Console acquisition: Store listing visitors -> First-time installers.
- Product activation: installed users -> created/joined group -> real expense or
  settlement in `first-100-cohort-tracker.csv`.

If a store variant increases installs but produces inactive users, it is not a
win for this launch.
