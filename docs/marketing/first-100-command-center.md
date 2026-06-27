# Rihla First-100 Command Center

Date: 2026-06-27

Objective: reach 100 real Android users by recruiting group champions who create
real Rihla groups, invite friends, and record real shared expenses.

## Current Launch State

Verified this session:

- Landing page is live at `https://rihla-safar.web.app/`.
- Live page includes the SEO title, meta description, `SoftwareApplication`
  JSON-LD, and Google Play CTAs.
- Live page includes a typed invite-code form that routes valid 6-character
  codes to `/join/<CODE>`.
- Arabic landing page is live at `https://rihla-safar.web.app/ar` with
  reciprocal `hreflang` links.
- Oman split-bills SEO pages are live at `/split-bills-oman` and
  `/ar/split-bills-oman`, including FAQ structured data and Play CTAs.
- All four public landing pages include the alpha-access fallback for users who
  see Google Play unavailable before they are added as testers.
- Dedicated alpha access pages are available at `/alpha` and `/ar/alpha` for
  testers who need the Play opt-in and wrong-account steps.
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
- `closed-test-access-kit.md` now defines the Play alpha opt-in workflow,
  private tester-email handling, and access-first messages for the first cohort.
- `tool/export_play_tester_emails.dart` now turns the private tester roster into
  a Play Console upload file without committing real emails.
- `tool/first_100_launch_packet.dart` now turns a private first-10 roster into a
  Play upload CSV, paste-ready DMs, a send sheet, and a launch checklist in one
  private output folder.
- `tool/first_100_launch_packet.dart --include-existing-testers=...` preserves
  already-active Play tester emails in the upload CSV so later batches do not
  accidentally remove earlier tester access.
- `tool/first_100_launch_packet.dart --write-roster-template=...` now exports
  the first empty tracker slots into a blank private roster template so
  champion names and Google Play emails stay outside git.
- `tool/first_100_roster_check.dart` now checks a filled private roster before
  Play upload or message generation without printing champion names or tester
  emails.
- `tool/first_100_tracker_patch.dart` now applies a filled private roster to a
  private tracker copy after messages are sent, without carrying Play tester
  emails into the tracker output.
- `tool/first_100_followups.dart` now generates privacy-safe follow-up prompts
  from due tracker rows without printing champion names.
- `tool/play_acquisition_summary.dart` now turns a private weekly Play Console
  acquisition log into a store-listing conversion summary and experiment gate
  without committing Play metrics or tester data.
- `short-video-content-kit.md` now gives ready-to-record Reels/TikTok/WhatsApp
  Status scripts with tracked install and alpha access links.
- `public-channel-hit-list.md` now maps permission-first public/community
  outreach targets for the second wave after the first 10 warm asks.
- `play-store-aso-conversion-plan.md` now turns Play Store visibility, custom
  listings, SEO expansion, and listing experiments into a measured loop tied to
  the first-100 tracker.

Known growth blocker:

- The tracker still has no named champions. The next constraint is not SEO copy;
  it is getting the first 10 real people added to Play testing, opted in,
  installed, and using one real shared bill.
- Because Rihla is still on a controlled Play alpha track, every closed-test DM
  must include the private Play opt-in link before the tracked landing-page link.

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
empty slots without printing private champion names or tester emails.

| Day | Date | Champions contacted | Tester-added | Groups created | Invites sent | Installs reported | Joined users | Activated groups | Top blocker |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 2026-06-27 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | Champion list not filled |
| 2 |  |  |  |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |  |  |  |
| 4 |  |  |  |  |  |  |  |  |  |
| 5 |  |  |  |  |  |  |  |  |  |
| 6 |  |  |  |  |  |  |  |  |  |
| 7 |  |  |  |  |  |  |  |  |  |

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
2. Generate the private roster template from the next empty tracker rows:
   `dart tool/first_100_launch_packet.dart --write-roster-template="$HOME/Desktop/rihla-first-10-roster.csv"`.
3. Fill the generated private roster with 10 real champion names and Google Play
   emails. Keep this file out of git.
4. Ask for the Google account they use in Play if they are not already a tester.
5. Confirm or adjust each row's language, segment, real use case, and channel.
6. Check the private roster before Play upload or message generation:
   `dart tool/first_100_roster_check.dart ~/Desktop/rihla-first-10-roster.csv`.
7. Export the private opt-in link:
   `export RIHLA_PLAY_OPT_IN_LINK="PASTE_PLAY_CONSOLE_OPT_IN_LINK"`.
8. Build the private launch packet, preserving already-active testers if this
   is not the first Play upload:

   ```bash
   dart tool/first_100_launch_packet.dart ~/Desktop/rihla-first-10-roster.csv \
     --play-opt-in-link="$RIHLA_PLAY_OPT_IN_LINK" \
     --include-existing-testers="$HOME/Desktop/rihla-active-play-testers.csv" \
     --output-dir=/tmp/rihla-first-10-launch-packet
   ```

9. Upload `/tmp/rihla-first-10-launch-packet/play-testers.csv` to Play closed
   testing if required, then copy that generated file to
   `~/Desktop/rihla-active-play-testers.csv` as the next batch's active list.
10. Send messages from `/tmp/rihla-first-10-launch-packet/send-sheet.md`,
   using `/tmp/rihla-first-10-launch-packet/outreach-messages.md` as the full
   message source.
11. Patch the private tracker copy after the batch is sent:

   ```bash
   dart tool/first_100_tracker_patch.dart \
     docs/marketing/first-100-cohort-tracker.csv \
     "$HOME/Desktop/rihla-first-10-roster.csv" \
     --today=YYYY-MM-DD \
     --mark-tester-added \
     --mark-contacted \
     --output="$HOME/Desktop/rihla-first-100-tracker.csv"
   ```

   Keep `~/Desktop/rihla-first-100-tracker.csv` out of git. It may contain
   champion names, but it must not contain Google Play tester emails.
12. Send `/alpha` or `/ar/alpha` only when they need the Google Play access
   steps explained separately.
13. Use `/tmp/rihla-first-10-launch-packet/checklist.md` to update the private
   tracker after each response.
14. Follow up within 24 hours with one concrete ask: create group, invite people,
   or add first expense.
15. Record the exact blocker in the tracker, not a vague note.
16. Generate due follow-ups:
    `dart tool/first_100_followups.dart --today=YYYY-MM-DD`.
17. Run
    `dart tool/first_100_summary.dart "$HOME/Desktop/rihla-first-100-tracker.csv" --today=YYYY-MM-DD`
    and use its recommended next action for the next batch.

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
| Contacted -> tester added | 70% | Tester access is unclear; send direct access instructions. |
| Tester added -> installed | 75% | Play access/link friction; move toward open testing or clearer links. |
| Installed -> group created/joined | 65% | First-run/empty-state unclear; improve the champion script and app entry path. |
| Invite sent -> invitee joined | 60% | Inspect install-referrer behavior and tighten invite page copy. |
| Group joined -> first expense | 60% | Prioritize first-expense speed (`#245`) and champion coaching. |

## Day-1 Execution

Use `day-1-outreach.md` for the first 10 slot-specific messages, links, Play
access checks, and 24-hour follow-up prompts.

Use `closed-test-access-kit.md` whenever a champion is not already able to
install from the Play alpha.

Use `tool/first_100_messages.dart` only for ad hoc single-language batches. The
preferred first-10 path is `tool/first_100_launch_packet.dart` because it keeps
the Play upload, opt-in link, messages, and checklist together.

Use `tool/first_100_launch_packet.dart --write-roster-template=...` before the
first private batch. It copies the next empty public tracker slots and leaves
`champion` and `google_play_email` blank so private data is filled locally only.

Use `tool/first_100_roster_check.dart ~/Desktop/rihla-first-10-roster.csv`
before generating the launch packet. It reports only slot numbers and issue
types, so roster mistakes can be fixed without leaking names or emails into
terminal output.

Use `/tmp/rihla-first-10-launch-packet/send-sheet.md` as the send queue after
Play access is ready. It keeps the slot, channel, tracked link, message anchor,
and WhatsApp draft link together without printing tester emails.

Use `tool/first_100_tracker_patch.dart` after sending the batch to write
`~/Desktop/rihla-first-100-tracker.csv` from the public tracker plus the private
roster. The tool reports only updated slot numbers in terminal output and does
not carry Google Play tester emails into the tracker CSV.

Use `--include-existing-testers="$HOME/Desktop/rihla-active-play-testers.csv"`
on every launch-packet upload after the first one. Google Play CSV uploads can
replace the tester list, so each generated upload must include people who
already have alpha access.

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
  too vague or tester access is blocking.
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
