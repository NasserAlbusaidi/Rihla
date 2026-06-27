# First 100 Outreach Kit

Date: 2026-06-27

Purpose: recruit 40 group champions who can bring Rihla into real WhatsApp groups, trips, dinners, roommate bills, or coworker/shared-cost situations.

Use alongside:

- `first-100-command-center.md` for the daily scorecard, segment quotas, and
  decision rules.
- `first-100-cohort-tracker.csv` for the 40 champion slots and actual outreach
  state.
- `day-1-outreach.md` for the first 10 slot-specific messages and follow-ups.
- `closed-test-access-kit.md` for Play alpha opt-in instructions before sending
  install asks.
- `public-channel-hit-list.md` for permission-first public/community targets
  once the first 10 warm champion asks are in motion.
- `short-video-content-kit.md` for ready-to-record Reels, TikTok, WhatsApp
  Status scripts, and tracked captions.
- `tool/first_100_launch_packet.dart` to generate the private first-10 Play
  upload file, outreach messages, and send checklist in one step.
- `tool/first_100_launch_packet.dart --write-roster-template=...` to start a
  private roster from the next empty public tracker slots without committing
  champion names or Google Play emails.
- `tool/first_100_followups.dart` to generate slot-based follow-up prompts for
  due tracker rows without exposing champion names.
- `tool/play_acquisition_summary.dart` to summarize weekly Play Console
  visitors, first-time installers, and tracker activation before changing store
  copy or screenshots.
- `tool/first_100_messages.dart` to generate slot-specific DM copy with tracked
  links from the cohort tracker.

## Trackable Links

Use landing-page links in outreach rather than raw Play links. The landing pages
preserve `utm_*` parameters into the Play Store `referrer` parameter when a user
taps the Google Play CTA.

English direct outreach:

`https://rihla-safar.web.app/?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100&utm_content=champion_slot_XX`

Arabic direct outreach:

`https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_XX`

Oman use-case page:

`https://rihla-safar.web.app/split-bills-oman?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_oman&utm_content=champion_slot_XX`

Replace `XX` with the tracker slot number. Keep the raw Play link only for users
who explicitly say the landing page will not open.

Generate the next message batch instead of hand-editing links:

```bash
dart tool/first_100_messages.dart --count=10 --language=en
dart tool/first_100_messages.dart --count=10 --language=ar
```

For the first 10 private champions, prefer one launch packet so Play upload,
messages, and checklist stay in sync:

```bash
dart tool/first_100_launch_packet.dart \
  --write-roster-template="$HOME/Desktop/rihla-first-10-roster.csv"

export RIHLA_PLAY_OPT_IN_LINK="PASTE_PLAY_CONSOLE_OPT_IN_LINK"
dart tool/first_100_launch_packet.dart ~/Desktop/rihla-first-10-roster.csv \
  --play-opt-in-link="$RIHLA_PLAY_OPT_IN_LINK" \
  --output-dir=/tmp/rihla-first-10-launch-packet
```

For closed-test outreach, inject the private Play Console opt-in link into the
generated message after the tester is added:

```bash
export RIHLA_PLAY_OPT_IN_LINK="PASTE_PLAY_CONSOLE_OPT_IN_LINK"
dart tool/first_100_messages.dart --count=10 --language=en \
  --play-opt-in-link="$RIHLA_PLAY_OPT_IN_LINK"
```

Keep the real `RIHLA_PLAY_OPT_IN_LINK` out of git and send it only to approved
testers. The generated message will put the tester opt-in step before the
tracked landing-page link.

After first contact, generate due follow-up prompts from the tracker:

```bash
dart tool/first_100_followups.dart --today=YYYY-MM-DD
```

The follow-up output uses tracker slot numbers and funnel stages, not champion
names, so it is safe to paste into planning notes.

After the first batch has a week of Play Console data, create and fill the
private acquisition log, then summarize it before making any ASO change:

```bash
dart tool/play_acquisition_summary.dart \
  --write-template="$HOME/Desktop/rihla-play-acquisition-log.csv"

dart tool/play_acquisition_summary.dart \
  "$HOME/Desktop/rihla-play-acquisition-log.csv" \
  docs/marketing/first-100-cohort-tracker.csv
```

If the summary says the experiment gate is closed, send more direct asks before
changing the Play Store listing.

## Operating Rule

Do not ask people to "try the app" in the abstract. Ask them to use Rihla for one real shared bill with a real group.

Good ask:

> Can you use Rihla for your next group dinner or trip this week? Create a group, send the WhatsApp invite, and add the first real expense.

Weak ask:

> Download my app and let me know what you think.

## Target Numbers

- 40 named champions contacted.
- 30 groups created.
- 100 total users from those groups.
- 60 activated users.
- 20 activated groups.

Activated user: installed Rihla and joined or created a group with at least one real shared-expense action.

Activated group: 3+ members and at least 2 real expenses or 1 settlement.

## Champion Segments

### Travel Crews

Who:

- Friends planning Salalah, camping, chalet, weekend, road-trip, or flight trips.
- People who usually pay upfront for bookings or food.

Message angle:

> Track every shared expense on the trip and settle up in the fewest payments.

### Roommates

Who:

- Flatmates splitting groceries, utilities, small purchases, or rent extras.

Message angle:

> Keep one group for the flat and always know who owes who.

### Dinner and Majlis Groups

Who:

- Friend groups that rotate payments for meals, coffee, groceries, or gatherings.

Message angle:

> Add the bill in seconds and settle clearly before people forget.

### Coworker and Student Groups

Who:

- Office lunch groups, university friends, student clubs, project groups.

Message angle:

> No signup, just create the group and share the WhatsApp invite.

## English Outreach Scripts

### First Message

```text
I just released Rihla on Google Play alpha.

It is for splitting group expenses with friends - no signup, Arabic/English, OMR-friendly, and works offline.

Can you try it with one real group this week? Best use case is a dinner, trip, groceries, or shared bill.

Create a group, share the WhatsApp invite, and add the first expense. I only need honest usage and feedback from real groups.
```

### Short Version

```text
Can you test Rihla with one real group this week?

Use it for a dinner, trip, or shared bill: create group -> send WhatsApp invite -> add first expense.

Trackable link: https://rihla-safar.web.app/?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100&utm_content=champion_slot_XX
```

### Follow-Up After Install

```text
Did everyone manage to join the group?

If yes, add one real expense now while it is fresh. That is the moment I need to test: invite -> join -> first expense -> who owes who.
```

### Follow-Up After First Expense

```text
What was confusing or slow before the first expense got added?

I am trying to fix the path to the first real shared bill, not collect compliments.
```

### Ask for More Groups

```text
This is useful. Can you forward the app to 2 people who regularly split costs with a group?

Best people: someone planning a trip, someone with roommates, or someone who organizes group dinners.
```

## Arabic Outreach Scripts

### First Message

```text
أطلقت تطبيق Rihla على Google Play alpha.

فكرته بسيطة: تقسيم مصاريف الشلة ومعرفة من يدين لمن - بدون تسجيل، يدعم العربي والإنجليزي، مناسب للريال العماني، ويعمل بدون اتصال.

ممكن تجربه مع مجموعة حقيقية هذا الأسبوع؟ أفضل استخدام: عشاء، رحلة، مشتريات، أو فاتورة مشتركة.

أنشئ مجموعة، أرسل رابط الدعوة في واتساب، وأضف أول مصروف حقيقي. أحتاج تجربة حقيقية وملاحظات صريحة.
```

### Short Version

```text
ممكن تجرب Rihla مع مجموعة حقيقية هذا الأسبوع؟

استخدمه لعشاء، رحلة، أو فاتورة مشتركة:
أنشئ مجموعة -> أرسل دعوة واتساب -> أضف أول مصروف.

رابط Android alpha:
https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm&utm_campaign=first_100_ar&utm_content=champion_slot_XX
```

### Follow-Up After Install

```text
هل قدروا كلهم يدخلوا المجموعة؟

إذا نعم، أضف مصروف حقيقي الآن قبل ما تنسوه. هذه أهم تجربة أحتاجها: دعوة -> دخول -> أول مصروف -> معرفة من يدين لمن.
```

### Follow-Up After First Expense

```text
ما الشيء الذي كان مربك أو بطيء قبل إضافة أول مصروف؟

أحتاج أعرف أين يتعطل المستخدم قبل الاستخدام الحقيقي.
```

## Instagram / TikTok Content Prompts

Use `short-video-content-kit.md` for the current 10-video posting set. The
prompts below are retained as the simple source angles.

Keep every video 8-15 seconds. Use real screen recording where possible.

### Video 1: Dinner Bill

Hook:

> One person paid for dinner. Now what?

Beats:

1. Show restaurant bill / group chat context.
2. Open Rihla.
3. Add amount.
4. Show who owes who.

Caption:

```text
Split dinner with your group without signup. Rihla is on Android alpha:
https://rihla-safar.web.app/alpha?utm_source=instagram&utm_medium=video&utm_campaign=first_100_alpha&utm_content=legacy_dinner
```

### Video 2: Salalah / Trip

Hook:

> Trip expenses get messy fast.

Beats:

1. Fuel / stay / food labels.
2. Rihla group screen.
3. Add expense.
4. Settle up screen.

Caption:

```text
For trips, dinners, and shared bills in Oman/GCC. Arabic + English:
https://rihla-safar.web.app/split-bills-oman?utm_source=instagram&utm_medium=video&utm_campaign=first_100_oman&utm_content=legacy_trip
```

### Video 3: WhatsApp Invite

Hook:

> Send the group invite on WhatsApp.

Beats:

1. Rihla invite sheet.
2. WhatsApp button.
3. Friend opens invite.
4. Join screen.

Caption:

```text
Create a Rihla group, send the invite, and split the first expense. No signup:
https://rihla-safar.web.app/?utm_source=instagram&utm_medium=video&utm_campaign=first_100&utm_content=legacy_invite
```

## Weekly Cadence

### Day 1

- Confirm Play alpha access for each target champion.
- Contact 10 champions.
- Track every champion in `first-100-cohort-tracker.csv`.
- Help the first 3 create groups manually if needed.

### Day 2

- Fix any wrong-Google-account or opt-in-link failures from Day 1.
- Contact 10 more champions.
- Follow up with Day 1 champions who installed but did not create a group.

### Day 3

- Contact 10 more champions.
- Ask every created group to add one real expense.

### Day 4

- Contact final 10 champions.
- Post the first short video.

### Day 5

- Review dropoff:
  - contacted -> installed
  - installed -> group created/joined
  - group -> first expense
  - invite sent -> invitee joined

### Day 6-7

- Fix the top blocker.
- Ask activated champions for 2 more intros.
- Publish the second and third short videos.

## Feedback Questions

Ask these after a real expense, not before:

1. What made you hesitate before creating or joining the group?
2. Was the invite flow clear?
3. Was adding the first expense fast enough?
4. Did the balance / who-owes-who result make sense?
5. Would you use this again for the same group?
6. Who else should try this?

## Manual Reporting Format

Every evening, write a short update:

```text
Date:
Champions contacted:
New installs:
Groups created:
Successful joins:
Groups with first expense:
Activated groups:
Top blocker:
Fix / next action:
```

## Non-Negotiables

- Do not buy ads before 20 activated groups.
- Do not optimize screenshots before there is enough traffic to learn.
- Do not count installs as success if groups do not activate.
- Do not ask for public reviews until users have completed a useful group moment.
- Do not collect contacts, precise location, or ad identifiers for this milestone.
- Do not commit real tester emails to git.
