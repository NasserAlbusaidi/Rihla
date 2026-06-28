# Rihla Public Channel Hit List

Date: 2026-06-27

Purpose: create a permission-first list of public or semi-public channels where
Rihla can find group champions beyond the first 10 warm personal asks.

This is not a replacement for personal outreach. Use it after the first 10 named
champions are contacted, or in parallel only if the message is sent manually and
respectfully.

## Operating Rules

- Do not scrape names, emails, phone numbers, Reddit usernames, Instagram
  handles, or WhatsApp links into this repo.
- Do not mass-DM strangers.
- Do not post install links into a community without reading the rules and
  getting permission when promotion is unclear.
- Always ask moderator permission for forums, subreddits, student groups, and
  private communities before posting.
- Use one channel-specific tracked link per post so installs can be attributed:
  `https://rihla-safar.web.app/?utm_source=community&utm_medium=post&utm_campaign=first_100_public&utm_content=CHANNEL_SLUG`
- For Arabic-first groups, use:
  `https://rihla-safar.web.app/ar?utm_source=community&utm_medium=post&utm_campaign=first_100_public_ar&utm_content=CHANNEL_SLUG`
- The tracked link routes straight to the public Play listing, so a post can
  send people to install directly. No tester list, opt-in link, or Google
  account to collect.

## Availability

Rihla is live in public production on Google Play at 100% rollout. Anyone can
install it directly from the public Play listing — there is no closed-testing
track, no tester allow-list, no opt-in link, and no Google account to collect.
A public-channel post can route people straight to the tracked link, which
carries attribution into the Play install referrer.

Operational implication: every public channel post still asks for a small real-
group test and honest feedback — that is the value, not access. Keep it
permission-first and wave-2.

## Priority Channels

| Priority | Channel | Source | Why it fits Rihla | First action | Message angle | Tracking slug |
|---:|---|---|---|---|---|---|
| 1 | Warm personal WhatsApp groups | Private, not in repo | Highest trust and fastest path to real groups. | Fill tracker slots 1-10 with real names. | "Use this for one real shared bill this week." | `warm_whatsapp_01` |
| 2 | InterNations Muscat | https://www.internations.org/muscat-expats | Expat groups often split dinners, trips, and shared outings. | Join, attend or message event organizer, ask whether a tester ask is allowed. | "No signup bill splitter for Muscat dinners and trips." | `internations_muscat` |
| 3 | Eventbrite Muscat events | https://www.eventbrite.com/d/oman/muscat/ | Event organizers and attendees create repeated group outings. | Pick 5 relevant social, tech, travel, student, or networking events and message organizers. | "Free tool for groups who split event, dinner, or travel costs." | `eventbrite_muscat` |
| 4 | Meetup Oman social/networking groups | https://www.meetup.com/topics/socialnetwork/om/ | Meetup communities already gather strangers for recurring social plans. | Contact group organizers before posting. | "Try it at the next group meal or activity." | `meetup_oman_social` |
| 5 | r/Oman | https://www.reddit.com/r/Oman/ | Broad Oman community with locals, expats, and travel/life questions. | Ask moderators whether a feedback post is acceptable. | "Oman-built Android app looking for 20 real group testers." | `reddit_oman` |
| 6 | r/omantravel / Oman travel discussions | https://www.reddit.com/r/omantravel/ | Travel groups have a strong split-expense use case. | Ask moderators or comment only where app mention directly answers a split-cost need. | "For Salalah, camping, road trips, and group bookings." | `reddit_omantravel` |
| 7 | Sultan Qaboos University student groups | https://www.squ.edu.om/student-affairs/Home | SQU has many student societies and activity groups; student groups create trips, events, and shared purchases. | Reach known students or society leads, not random public emails. | "Use it for club outings, project expenses, and group meals." | `squ_student_groups` |
| 8 | SQU Economics / Business student groups | https://www.squ.edu.om/economics/Student/Students-groups | Business and finance groups are naturally aligned with expense tracking. | Ask a student lead to run a 5-person beta in one event. | "Finance-minded beta: settle one event without spreadsheets." | `squ_business_groups` |
| 9 | SQU Information Technology Society | https://www.squ.edu.om/student-affairs/Information-technology-IT-society | Tech students can give sharper product feedback and bring Android users. | Ask for testers with Android phones and real group use cases. | "Local Flutter/Firebase app seeking product feedback." | `squ_it_society` |
| 10 | GUtech student clubs | https://www.gutech.edu.om/student-campus-life/ | GUtech student clubs cover academics, media, community service, arts, cultural, and environmental interests. | Contact Registration and Student Affairs or a known club member. | "Use for club event purchases and group meals." | `gutech_clubs` |
| 11 | MCBS student clubs | https://www.mcbs.edu.om/student-life/student-clubs/ | MCBS lists active clubs and campus groups; student clubs are likely group-spend settings. | Ask one club lead for 3 Android testers. | "One club, one real event, one shared bill." | `mcbs_student_clubs` |
| 12 | MCBS International Club | https://www.mcbs.edu.om/student-life/student-clubs/international-club-2/ | Cross-cultural and international student groups often coordinate group outings. | Ask before contacting named people; keep outreach permission-based. | "Arabic/English no-signup split bills for mixed groups." | `mcbs_international` |
| 13 | Oman Tourism College alumni/student community | https://www.otc.edu.om/portal/contact/alumni/ | Tourism/hospitality students and alumni overlap with trips, outings, and event planning. | Use official contact channels or personal intros only. | "Trip and outing expense tracker for hospitality groups." | `otc_alumni` |
| 14 | Expat community/event directories | https://www.omanmbd.com/diplomacy/community-events | International-community events create recurring social groups. | Identify event organizers; ask for 3-5 Android testers, not a public blast. | "Help us test a local bill-splitting app at one real outing." | `oman_expat_events` |

## Seven-Day Channel Plan

Day 1:

- Fill the first 10 warm champion slots.
- Send the generated Day-1 messages, each with the champion's tracked link.

Day 2:

- DM or personally ask 5 more known people in the travel, dinner, roommate, or
  student segments.
- Ask one current student contact for an SQU/GUtech/MCBS intro.

Day 3:

- Contact 3 Eventbrite or Meetup organizers with permission-first copy.
- Do not post publicly yet unless permission is granted.

Day 4:

- Draft a moderator request for r/Oman and r/omantravel.
- Ask for permission to post a feedback thread, not an ad.

Day 5:

- Follow up with warm champions who installed but did not create a group.
- If fewer than 7 people installed, stop public posting and fix the warm-funnel
  install friction first.

Day 6:

- Post only in channels that granted permission.
- Track every public/community post with `utm_source=community`.

Day 7:

- Run `dart tool/first_100_summary.dart --today=YYYY-MM-DD`.
- Compare channel-driven installs against warm champion installs.
- Keep only channels that produce activated groups, not vanity clicks.

## Permission Request Copy

English:

```text
Hi, I am testing Rihla, an Android app built in Oman for splitting group
expenses with friends. It is useful for trips, dinners, student clubs, and
roommate/shared bills.

Would it be acceptable to post a short request for testers here? I am looking
for a few Android users who can try it with one real group bill and send honest
feedback. I will keep it short and will not spam the group.
```

Arabic:

```text
مرحبًا، أختبر تطبيق Rihla على Android. التطبيق مخصص لتقسيم مصاريف
المجموعات مثل الرحلات، العشاء، أنشطة الطلاب، أو مصاريف السكن المشترك.

هل مسموح أن أنشر طلبًا قصيرًا لمختبرين للتطبيق؟ أبحث عن عدد قليل من مستخدمي
Android يجربونه مع فاتورة مجموعة حقيقية ويرسلون ملاحظات صريحة. سأبقي المنشور
قصيرًا ولن أكرر النشر.
```

## Approved Post Copy

English:

```text
Oman Android testers wanted.

I am testing Rihla, a no-signup app for splitting shared expenses with friends.
Best use case: a trip, dinner, groceries, fuel, roommate bill, or club event
where one person pays and everyone needs to settle clearly.

I am looking for people who can use it with one real group this week:
1. install Rihla from Google Play
2. create one group
3. invite 2+ people
4. add one real shared expense
5. tell me what blocked or confused you

Install: TRACKED_LINK
```

Arabic:

```text
أبحث عن مختبرين في عمان لتطبيق Rihla على Android.

Rihla يساعدك على تقسيم مصاريف المجموعة بدون تسجيل: رحلة، عشاء، مشتريات، بترول،
فاتورة سكن مشترك، أو فعالية طلابية.

أحتاج أشخاص يجربونه مع مجموعة حقيقية هذا الأسبوع:
1. تثبّت Rihla من Google Play
2. تنشئ مجموعة
3. تدعو شخصين أو أكثر
4. تضيف مصروفًا حقيقيًا مشتركًا
5. تخبرني ما الذي عطلك أو كان غير واضح

الرابط: TRACKED_LINK
```

## Measurement Rules

- `first_contact_date`: set only when a human is contacted or a public post is
  made.
- `contact_channel`: use `community:<slug>` for public-channel leads.
- `tester_added`: set to `yes` only after the person has installed Rihla from
  Google Play. Column name is kept for the tooling; it now means "confirmed
  installed".
- `top_blocker`: use exact values such as `moderator denied`, `no Android`,
  `installed no group`, or `joined no expense`.
- A public channel is worth repeating only if it produces at least one activated
  group, not just clicks.

