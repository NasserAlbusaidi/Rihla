# Rihla First-100 Command Center

Date: 2026-06-27

Objective: reach 100 real Android users by recruiting group champions who create
real Rihla groups, invite friends, and record real shared expenses.

## Current Launch State

Verified this session:

- Rihla v1.6.3 is live in public production on Google Play at 100% rollout.
  Anyone can install directly from the public Play listing or the landing-page
  Play CTA. There is no closed-testing track, tester allow-list, or opt-in step.
- Landing page is live at `https://rihla-safar.web.app/`.
- Live page includes the SEO title, meta description, `SoftwareApplication`
  JSON-LD, and Google Play CTAs.
- Live page includes a typed invite-code form that routes valid 6-character
  codes to `/join/<CODE>`.
- Arabic landing page is live at `https://rihla-safar.web.app/ar` with
  reciprocal `hreflang` links.
- Oman split-bills SEO pages are live at `/split-bills-oman` and
  `/ar/split-bills-oman`, including FAQ structured data and Play CTAs.
- The `/alpha` and `/ar/alpha` explainer pages still exist, but they are no
  longer an access gate — anyone can install directly from Play, so do not route
  champions there to get access.
- `robots.txt` and `sitemap.xml` are live for crawl discovery.
- Feature graphic asset returns `200` at
  `https://rihla-safar.web.app/assets/feature-graphic.png`.
- Play metadata was pushed and pulled back from Google Play. The live metadata
  export contains the new short descriptions plus the Oman/Gulf, WhatsApp,
  no-forced-signup, and optional email-recovery full-description positioning in
  English and Arabic.
- The app has no in-app analytics package in `pubspec.yaml` / `lib`, so the first
  cohort must be tracked with Play Console, Firebase/Firestore checks where safe,
  and the manual champion tracker.
- Public landing pages preserve `utm_source`, `utm_medium`, `utm_campaign`,
  `utm_content`, and `utm_term` into the Play Store `referrer` parameter for
  Google Play CTAs, so outreach should use the trackable URLs in
  `first-100-outreach-kit.md`.
- `tool/first_100_launch_packet.dart` now turns a private first-10 roster into
  paste-ready DMs, a send sheet, and a launch checklist in one private output
  folder.
- `tool/first_100_launch_packet.dart --write-roster-template=...` now exports
  the first empty tracker slots into a blank private roster template so champion
  names stay outside git.
- `tool/first_100_champion_sourcing.dart` now turns the next empty tracker slots
  into a private candidate worksheet, checks Android/live-bill readiness without
  printing names, and writes the private launch roster once candidates are ready.
- `tool/first_100_roster_check.dart` now checks a filled private roster before
  generating the launch packet without printing champion names.
- `tool/first_100_tracker_patch.dart` now applies a filled private roster to a
  private tracker copy after messages are sent.
- `tool/first_100_followups.dart` now generates privacy-safe follow-up prompts
  from due tracker rows without printing champion names.
- `tool/play_acquisition_summary.dart` now turns a private weekly Play Console
  acquisition log into a store-listing conversion summary and experiment gate
  without committing Play metrics.
- `short-video-content-kit.md` now gives ready-to-record Reels/TikTok/WhatsApp
  Status scripts with tracked install links.
- `public-channel-hit-list.md` now maps permission-first public/community
  outreach targets for the second wave after the first 10 warm asks.
- `play-store-aso-conversion-plan.md` now turns Play Store visibility, custom
  listings, SEO expansion, and listing experiments into a measured loop tied to
  the first-100 tracker.

Known growth blocker:

- The tracker still has no named champions. The next constraint is not SEO copy;
  it is getting the first 10 real people to install from Play, create or join a
  group, and use one real shared bill.

## North-Star Numbers

The first 100 should come from groups, not isolated cold installs.

| Metric | Target | Why it matters |
|---|---:|---|
| Named champions contacted | 40 | Enough group owners to reach 100 users. |
| Champions who create/share a group | 30 | Core distribution unit is a group chat. |
| Total real users | 100 | User-stated goal. |
| Activated users | 60 | Installed plus joined/created a group with a real expense action. |
| Activated groups | 20 | 3+ members and 2 expenses or 1 settlement. |
| Real expenses/settlements | 50 | Proves product usage, not installs only. |
| Written feedback notes | 10 | Enough signal to fix activation blockers. |

## Daily Scorecard

Update this once per day from `first-100-cohort-tracker.csv`.

Run the tracker summary before editing this table:

```bash
dart tool/first_100_summary.dart --today=YYYY-MM-DD
```

The summary intentionally reports counts, segment coverage, blockers, and next
empty slots without printing private champion names.

| Day | Date | Champions contacted | Tester-added | Groups created | Invites sent | Installs reported | Joined users | Activated groups | Top blocker |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 2026-06-27 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | Champion list not filled |
| 2 |  |  |  |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |  |  |  |
| 4 |  |  |  |  |  |  |  |  |  |
| 5 |  |  |  |  |  |  |  |  |  |
| 6 |  |  |  |  |  |  |  |  |  |
| 7 |  |  |  |  |  |  |  |  |  |

The `Tester-added` column maps to the retained CSV `tester_added` column, which
now means "confirmed installed from Play."

## Segment Quotas

Fill all 40 slots in `first-100-cohort-tracker.csv` before judging channel
performance.

| Segment | Champion slots | Expected group size | Target users |
|---|---:|---:|---:|
| Travel crews | 12 | 4-6 | 35 |
| Dinner / majlis groups | 10 | 3-5 | 25 |
| Roommates / shared housing | 8 | 3-4 | 18 |
| Coworkers / student groups | 6 | 3-5 | 14 |
| Family / community groups | 4 | 4-6 | 10 |

## Daily Operating Loop

1. Run `dart tool/first_100_summary.dart --today=YYYY-MM-DD`.
2. Generate the private candidate worksheet from the next empty tracker rows:

   ```bash
   dart tool/first_100_champion_sourcing.dart \
     --write-template="$HOME/Desktop/rihla-first-10-candidates.csv"
   ```

3. Fill `~/Desktop/rihla-first-10-candidates.csv` with real warm candidates:
   name, relationship, language, Android likelihood, group size, live shared
   bill, and priority. Use `yes` for Android/live-bill readiness and `1`, `2`,
   or `3` for priority. Keep this file out of git.
4. Screen candidates and write the launch roster:

   ```bash
   dart tool/first_100_champion_sourcing.dart \
     "$HOME/Desktop/rihla-first-10-candidates.csv" \
     --write-roster="$HOME/Desktop/rihla-first-10-roster.csv"
   ```

   The terminal summary prints only counts and ready slot numbers; candidate
   names go only into the private roster file. (If the first 10 names are already
   chosen, you can skip sourcing and write a blank roster directly with
   `dart tool/first_100_launch_packet.dart --write-roster-template=...`.)
5. Personalize the slot message from "Messages To Send Today" and send it with
   the champion's tracked landing link.
6. Log `first_contact_date` and `follow_up_date` for each champion you contacted.
7. Follow up within 24 hours with one concrete ask: create group, invite people,
   or add first expense.
8. Record the exact blocker in the tracker, not a vague note.
9. Generate due follow-ups:
   `dart tool/first_100_followups.dart --today=YYYY-MM-DD`.
10. Re-run `dart tool/first_100_summary.dart --today=YYYY-MM-DD` and use its
    recommended next action for the next batch.

Do not send a generic broadcast until at least 20 personal asks have been sent.

## Weekly Play Acquisition Loop

Run this only after the first batch has been sent and Play Console has a week of
Store listing data:

```bash
dart tool/play_acquisition_summary.dart \
  --write-template="$HOME/Desktop/rihla-play-acquisition-log.csv"
```

Fill the private CSV from Play Console with Store listing visitors,
first-time installers, country/language/search-term context when available, and
the tracker installs/activated groups for the same date range. Then run:

```bash
dart tool/play_acquisition_summary.dart \
  "$HOME/Desktop/rihla-play-acquisition-log.csv" \
  docs/marketing/first-100-cohort-tracker.csv
```

If the output says the experiment gate is closed, keep the current listing and
send more champion asks. Do not start a Play Store experiment until both the
first-100 tracker and Play traffic floor support it.

## Conversion Targets

Use these targets to decide whether the first cohort is healthy.

| Funnel step | Healthy threshold | Action if below target |
|---|---:|---|
| Contacted -> installed | 70% | The ask or link is unclear; resend the trackable link with a concrete first-bill ask. |
| Installed -> group created/joined | 65% | First-run/empty-state unclear; improve the champion script and app entry path. |
| Invite sent -> invitee joined | 60% | Inspect install-referrer behavior and tighten invite page copy. |
| Group joined -> first expense | 60% | Prioritize first-expense speed (`#245`) and champion coaching. |

## Day-1 Execution

Use `day-1-outreach.md` for the first 10 slot-specific messages, links, and
24-hour follow-up prompts.

Use `tool/first_100_messages.dart` only for ad hoc single-language batches. The
preferred first-10 path is `tool/first_100_launch_packet.dart` because it keeps
the paste-ready messages, send sheet, and checklist together.

Use `tool/first_100_launch_packet.dart --write-roster-template=...` before the
first private batch. It copies the next empty public tracker slots and leaves
`champion` blank so private data is filled locally only.

Use `tool/first_100_champion_sourcing.dart` when the roster is still blank:

```bash
dart tool/first_100_champion_sourcing.dart \
  --write-template="$HOME/Desktop/rihla-first-10-candidates.csv"

dart tool/first_100_champion_sourcing.dart \
  "$HOME/Desktop/rihla-first-10-candidates.csv" \
  --write-roster="$HOME/Desktop/rihla-first-10-roster.csv"
```

Fill candidate names and readiness fields in the private candidate worksheet
before writing the launch roster. The command prints only counts and slot
numbers in terminal output. A candidate is treated as ready only when Android,
group size, and a live shared bill are confirmed.

Use `tool/first_100_roster_check.dart ~/Desktop/rihla-first-10-roster.csv`
before generating the launch packet. It reports only slot numbers and issue
types, so roster mistakes can be fixed without leaking names into terminal
output.

Use `/tmp/rihla-first-10-launch-packet/send-sheet.md` as the send queue. It
keeps the slot, channel, tracked link, message anchor, and WhatsApp draft link
together.

Use `tool/first_100_tracker_patch.dart` after sending the batch to write
`~/Desktop/rihla-first-100-tracker.csv` from the public tracker plus the private
roster. The tool reports only updated slot numbers in terminal output.

Use `tool/first_100_followups.dart --today=YYYY-MM-DD` after the first messages
are sent. It prints due follow-up prompts by slot and stage without exposing
champion names.

Use `short-video-content-kit.md` for the first week of short-form posts. Treat
content as support for direct outreach, not a replacement for named champion
asks.

Use `public-channel-hit-list.md` only after the first 10 warm asks are sent or
when you have moderator/organizer permission. Public channels should supplement
the champion loop, not replace it.

Use `play-store-aso-conversion-plan.md` when the first warm outreach batch is in
motion and Play Console has enough Store listing visitors to compare conversion
changes. Do not run listing experiments before named champion outreach starts.

## Messages To Send Today

English:

```text
Can you use Rihla for one real shared bill this week?

Best case: a dinner, trip, groceries, or roommate bill.

Create a group, send the WhatsApp invite, and add the first expense while it is fresh. I need real usage, not compliments.

Trackable link: https://rihla-safar.web.app/?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100&utm_content=champion_slot_XX
```

Arabic:

```text
ممكن تستخدم Rihla لمصاريف مجموعة حقيقية هذا الأسبوع؟

أفضل تجربة: عشاء، رحلة، مشتريات، أو فاتورة سكن مشتركة.

أنشئ مجموعة، أرسل دعوة واتساب، وأضف أول مصروف وهو لا يزال جديد. أحتاج استخدام حقيقي، وليس مجاملة.

رابط تتبع:
https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_XX
```

Invite-install fallback:

```text
If you install from a group invite and the code is not filled automatically, go
back to the WhatsApp invite link and tap it again after installing.
```

## Weekly Decision Rules

- If fewer than 20 champions are contacted by day 3: pause SEO work and send more
  direct asks.
- If 20 champions are contacted but fewer than 8 groups are created: the ask is
  too vague or people are not installing.
- If groups are created but invitees do not join: inspect the invite/referrer
  handoff before more landing-page polish.
- If users join but do not add expenses: prioritize first-expense flow and
  champion coaching over new acquisition.
- If 60 activated users happen before 100 installs: ask those champions for two
  warm intros each.

## Proof Needed Before Calling The Goal Complete

- Play Console or equivalent install count shows at least 100 installs/users.
- Manual tracker or backend evidence shows at least 60 activated users.
- At least 20 activated groups are recorded.
- At least 50 real expenses/settlements are recorded.
- The top blockers are documented with next actions.
