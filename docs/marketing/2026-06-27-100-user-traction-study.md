# Rihla 100-User Traction Study

Date: 2026-06-27

Goal: get the first 100 real users to install Rihla, join or create a group, and use it for a real shared-expense moment.

## Execution Status

Published on 2026-06-27:

- Firebase Hosting root is live at `https://rihla-safar.web.app/` with the Android acquisition landing page, SEO title/description, Open Graph image, JSON-LD `SoftwareApplication`, and Google Play CTAs.
- The live landing page now includes a typed invite-code form that routes valid
  6-character codes to `/join/<CODE>`, so the secondary CTA no longer dead-ends
  at `/join` without a code.
- Arabic SEO landing page is live at `https://rihla-safar.web.app/ar`, with
  RTL copy, Arabic Play CTA, invite-code entry, and reciprocal `hreflang`
  alternates.
- Long-tail local SEO pages are live at
  `https://rihla-safar.web.app/split-bills-oman` and
  `https://rihla-safar.web.app/ar/split-bills-oman`, targeting "split bills in
  Oman", "Splitwise alternative for Oman", Arabic equivalents, OMR, no signup,
  and WhatsApp group invites.
- The English and Arabic landing pages now explain the Android alpha access
  fallback: if Google Play says Rihla is unavailable, users can request tester
  access with the Google account they use in Play.
- Dedicated alpha access pages are live at
  `https://rihla-safar.web.app/alpha` and
  `https://rihla-safar.web.app/ar/alpha`, giving testers the Play opt-in steps,
  wrong-account fix, and request-access CTA.
- Landing pages preserve `utm_*` outreach parameters into Google Play CTA
  `referrer` values, giving the first-100 campaign source-level attribution
  without cookies, contacts, precise location, or ad identifiers.
- `robots.txt` and `sitemap.xml` are live and expose the English landing page,
  Arabic landing page, Oman split-bills pages, alpha access pages, and
  trust/support URLs for crawlers.
- Hosting asset `https://rihla-safar.web.app/assets/feature-graphic.png` returns `200`.
- Invite fallback `https://rihla-safar.web.app/join/ABC123` returns `200` through Firebase Hosting rewrites.
- Google Play metadata was pushed with `bundle exec fastlane android listing`.
- A fresh Play metadata pull into `/tmp/rihla-play-metadata-pull-latest`
  verified the live API has the new short and full descriptions:
  - English: `Split group bills, see who owes who, settle up offline - no signup.`
  - Arabic: `قسّم مصاريف الشلة واعرف من يدين لمن - دون تسجيل ويعمل دون اتصال.`
  - English full description includes `Oman and the Gulf`, `WhatsApp`,
    `No signup required`, and `Optionally link an email`.
  - Arabic full description includes `عمان والخليج`, `واتساب`,
    `دون تسجيل إجباري`, and `استعادة اختيارية عبر البريد الإلكتروني`.
- `first-100-command-center.md` now converts this study into daily operating
  targets, scorecards, decision rules, and proof needed before the 100-user goal
  can be called complete.
- `closed-test-access-kit.md` now turns Play alpha access into a repeatable
  preflight workflow, including opt-in-link handling, private tester-email
  handling, and wrong-account troubleshooting.
- `tool/export_play_tester_emails.dart` now exports the private first-100 tester
  roster into a Play Console email-upload file without committing real emails.
- `first-100-cohort-tracker.csv` now contains 40 segment-assigned champion slots
  instead of blank rows, so outreach can start by replacing placeholders with
  real names and dates.
- `tool/first_100_summary.dart` now turns the tracker into a daily funnel
  summary without printing private champion names or tester emails.
- `short-video-content-kit.md` now provides 10 ready-to-record short videos with
  captions, tracked links, and a seven-day posting plan.

Not complete yet:

- The app still needs real users. The next measurable step is filling
  `docs/marketing/first-100-cohort-tracker.csv` with 40 real champion names and
  sending the first 10 personal asks from `docs/marketing/first-100-outreach-kit.md`.
- `#368` remains the highest-leverage product growth blocker because invite recipients can still lose the group code after installing from Play.

## Executive Decision

Rihla should not chase broad global ASO first. The fastest path to 100 real users is a founder-led, group-based launch in Oman/GCC, using WhatsApp invites and travel/roommate/dinner moments where the need already exists.

The best first wedge:

> Rihla is the no-signup, offline-friendly group bill splitter for Gulf friend groups who travel, eat, and settle up together.

The first 100 users should come from 20-30 seeded groups, not 100 isolated downloads. The core distribution unit is a group chat: one champion creates a Rihla group, shares the invite link, and pulls in 3-5 people.

SEO and Play Store visibility matter, but they are second-order for the first 100. They should support trust and conversion when someone receives an invite, not be treated as the main acquisition channel yet.

## Current Baseline

### Release and Availability

- User-provided release baseline: `v1.6.3+27`, release commit `77b7c96b`, Google Play alpha/closed-testing track.
- Git evidence during this study: `origin/main` points at `77b7c96b` and tag `v1.6.3`; the active local checkout is a stale feature branch at `d3ae1ab`.
- The app package is `com.safar.safar`.
- The Play upload track in CI is a custom closed-testing track named `first`.

Closed/alpha is enough for controlled acquisition, but it limits organic installability. The first 100 plan should either:

1. Add the target users as closed testers, or
2. Move to open testing/production once QA confidence is acceptable.

For growth measurement, closed-test installs are valid, but public reviews and broad organic discovery are not the main unlock until wider distribution.

### Store Listing Assets in Repo

Current English metadata after this pass:

- Title: `Rihla: Split Bills & Settle Up` - 30 characters.
- Short description: `Split group bills, see who owes who, settle up offline - no signup.` - 67 characters.
- Full description: 1731 characters in repo, 1730 characters from the latest
  pulled Play metadata export.
- Images: icon 512x512, feature graphic 1024x500, 4 English phone screenshots at 1242x2208.

Current Arabic metadata after this pass:

- Title: `Rihla — تقسيم وتسوية الفواتير` - 29 characters.
- Short description: `قسّم مصاريف الشلة واعرف من يدين لمن - دون تسجيل ويعمل دون اتصال.` - 64 characters.
- Full description: 1448 characters in repo, 1447 characters from the latest
  pulled Play metadata export.
- Images: 4 Arabic phone screenshots at 1242x2208.

The listing is already directionally strong: it includes split bills, settle up, who owes who, offline, Arabic, and Gulf currencies. The main ASO issue is conversion focus, not lack of keywords.

### Web and Invite Surfaces

Firebase Hosting exists at `rihla-safar.web.app` and includes:

- `/` root page.
- `/ar` Arabic landing page.
- `/split-bills-oman` English long-tail page.
- `/ar/split-bills-oman` Arabic long-tail page.
- `/join/<code>` invite fallback.
- `/privacy`, `/terms`, `/delete-data`, `/help`.
- App Links and Universal Links files.
- `robots.txt` and `sitemap.xml`.

At the start of this study, the root page was mostly a legal/support index and still said "iOS and Android". This pass replaced it with an Android-focused acquisition landing page with SEO title/description, Open Graph tags, JSON-LD, Google Play CTAs, use-case sections, and the existing Play feature graphic.

The invite page is much stronger:

- It opens `rihla://join/<code>`.
- It shows the invite code.
- It links to Google Play.
- It carries the invite code into the Play Store referrer: `referrer=code=<CODE>`.

Open issue `#368` is the missing growth loop: Android Play Install Referrer capture after install, one-shot route to `/join/<code>`, pre-fill only, no silent auto-join. This is high leverage for first-100 conversion.

### Product Strengths Relevant to Acquisition

From the product spec and current app surfaces:

- No signup on first launch.
- Anonymous by default, optional recovery email.
- Arabic and English support.
- RTL support.
- OMR/GCC-friendly money handling.
- Offline read/write behavior through Firestore persistence.
- WhatsApp invite CTA is implemented.
- Persistent groups across multiple trips/events.
- Group-level settle-up and event-level ledger.

The marketable edge is not "another Splitwise clone". It is Gulf-native, no-signup, offline, and built around recurring groups.

## External Research Findings

### Play Store Visibility and Conversion

Google Play's public guidance emphasizes that store listings should help users understand the app and that listing assets can be tested with store listing experiments. The relevant tools for Rihla:

- Main store listing text and screenshots.
- Store listing experiments for icon, screenshots, feature graphic, and localized text.
- Custom store listings for country/language-specific messaging.
- In-app review prompts after a strong user moment.
- Install Referrer API for attributing an invite/install flow.

Sources:

- Google Play store listing experiments: https://play.google.com/console/about/store-listing-experiments/
- Google Play custom store listings: https://support.google.com/googleplay/android-developer/answer/9867158
- Google Play app testing tracks: https://support.google.com/googleplay/android-developer/answer/9845334
- Google Play closed testing overview: https://play.google.com/console/about/closed-testing/
- Google Play personal account testing requirement: https://support.google.com/googleplay/android-developer/answer/14151465
- Google Play preview assets: https://support.google.com/googleplay/android-developer/answer/9866151
- Android in-app reviews: https://developer.android.com/guide/playcore/in-app-review
- Play Install Referrer API: https://developer.android.com/google/play/installreferrer

Important implication: ASO is an optimization layer, not a standalone launch plan. Rihla needs enough real traffic first before store experiments produce meaningful signal.

### SEO

Google Search's SEO guidance still starts with the basics: descriptive titles, useful page content, crawlable pages, and snippets that match what users search for. Rihla currently has an indexable Hosting root, but it does not yet target search intent like:

- split bills with friends Oman
- split expenses with friends
- settle up group expenses
- Splitwise alternative Oman
- expense splitter OMR
- تقسيم الفواتير بين الاصدقاء
- تقسيم المصاريف بين الشلة
- من يدين لمن

Source:

- Google Search Central SEO starter guide: https://developers.google.com/search/docs/fundamentals/seo-starter-guide

SEO will not produce the first 100 quickly, but the landing page should be fixed now because every invite recipient and search result uses it to judge trust.

### Oman/GCC Channel Context

Oman is a high-mobile, high-social market. DataReportal's Digital 2026 Oman report reports high internet and social-media penetration, and current app discovery for local consumer apps is heavily shaped by mobile/social sharing.

Source:

- DataReportal Digital 2026 Oman: https://datareportal.com/reports/digital-2026-oman

Practical takeaway: build around WhatsApp/Instagram sharing and Arabic/English copy. Do not begin with web SEO as the primary channel.

### Competitor Positioning

The main comparison set:

- Splitwise: broad shared-expense category leader.
- Tricount: group bills and trip expenses, simple collaborative positioning.
- Settle Up: group expense settlement positioning.
- Splid: offline/no-registration style positioning in parts of its copy.

Competitors usually win on category familiarity. Rihla can win a small first wedge by being more locally legible:

- Arabic and English from day one.
- OMR and GCC examples in screenshots.
- No account friction.
- Friend-group and WhatsApp-native sharing.
- Persistent crew across trips, not one-off trips only.

This is enough for 100 users if the ask is concrete and personal. It is not enough for broad organic ranking yet.

## Target User Segments

### Segment 1: Friend Travel Crews

Use case: Salalah Khareef trips, weekend stays, camping, road trips, short flights.

Why they adopt: someone always pays for food, fuel, stay, activities, or groceries and needs to settle later.

Best message:

> Going with the group? Track every shared expense and settle up in the fewest payments. No signup.

Primary channels:

- WhatsApp group chats.
- Instagram stories/reels.
- Local travel/camping accounts.
- Personal networks.

### Segment 2: Roommates and Shared Housing

Use case: rent add-ons, groceries, utilities, shared purchases.

Why they adopt: repeating expenses make persistent groups valuable.

Best message:

> Keep one group for the flat. Add bills as they happen. See who owes who.

Primary channels:

- University/student groups.
- Expat/community WhatsApp groups.
- Coworker networks.

### Segment 3: Dinner and Majlis Groups

Use case: restaurant bills, karak/coffee runs, weekly gatherings, family/friend meals.

Why they adopt: fast one-off expense entry and no signup are more important than deep features.

Best message:

> Someone paid for dinner? Add it in seconds and Rihla shows who owes who.

Primary channels:

- WhatsApp.
- Instagram short demos.
- Direct friend asks.

## Funnel Definition

The goal should not be "100 downloads" only. A useful first-100 funnel:

1. Store visitor or invite page visitor.
2. Install.
3. First open.
4. Create group or join group.
5. Add first real expense or settlement.
6. At least one more member joins the same group.

Recommended activation metric:

> Activated user = installed from Play, opened Rihla, and joined or created a group with at least one real shared-expense action.

Recommended group activation metric:

> Activated group = at least 3 members and at least 2 real expenses or 1 settlement.

For the first 100, group activation matters more than individual installs. Ten groups with genuine shared expenses are more valuable than 100 cold installs.

## 100-User Acquisition Model

Base math:

- Recruit 25 group champions.
- Each champion invites 4 people on average.
- 70% of champions actually create/share a group.
- 65% of invited people install and join.

Expected users:

- Champions activated: 25 x 70% = 17.5
- Invitees activated: 17.5 x 4 x 65% = 45.5
- Total: about 63 users.

That is not enough. The first campaign needs either more champions or higher group size.

Recommended target:

- 40 named champions.
- 30 create/share a group.
- Average 4 invitees per group.
- 60% invitee join rate.

Expected users:

- 30 champions.
- 30 x 4 x 60% = 72 invitees.
- Total: 102 users.

This is the concrete launch target: 40 named champions, with tracking per champion.

## Channel Plan

### Channel 1: Founder-Led Direct Seeding

Priority: highest.

Action:

- Fill the 40 segment-assigned slots in `first-100-cohort-tracker.csv` with real
  champion names.
- Each champion must be connected to a real group: trip, roommate, dinner, coworkers, club, family.
- Send each champion a personal message, not a broadcast.
- Help them create the first group if needed.
- Ask them to send the invite link while the use case is live.
- Update `first-100-command-center.md` daily from the tracker.

Champion script:

```text
I just released Rihla on Google Play alpha. It is for splitting group expenses with friends - no signup, works offline, Arabic/English, and supports OMR.

Can you try it with your group this week? Best use case is a dinner, trip, groceries, or shared bill.

Create a group, share the invite link in WhatsApp, and add the first expense. I only need honest usage and feedback from real groups.
```

Follow-up script after install:

```text
Did everyone manage to join the group? If yes, add one real expense now while it is fresh. The app is useful only after the first expense is in.
```

### Channel 2: WhatsApp Invite Loop

Priority: highest.

Already shipped:

- Invite link: `rihla-safar.web.app/join/<code>`.
- Google Play fallback on invite page.
- WhatsApp invite CTA in the app.
- Landing page invite-code entry routes typed codes to `/join/<code>`.

Missing:

- Android install referrer capture after Play install (`#368`).

Recommendation:

- Move `#368` to the top of the growth-supporting backlog.
- Do not silently auto-join from referrer. Keep pre-fill only.
- Add a simple local analytics/event log for invite page clicks if privacy posture allows, or use server logs safely.

### Channel 3: Instagram/TikTok Short Demos

Priority: medium-high.

Format:

- 8-15 second videos.
- Phone screen recording, not polished ad.
- Arabic and English variants.
- Show a real situation first, app second.

Video concepts:

1. "After a Salalah trip: 6 people, 1 person paid for the stay, 3 paid for food. Rihla says who owes who."
2. "No signup. Open, create group, send WhatsApp invite."
3. "Dinner bill chaos -> one expense -> settle up."
4. "Works offline on a road trip. Syncs later."

CTA:

> DM me for the Android alpha link.

Do not optimize for vanity likes. Track how many installs and activated groups each post creates.

### Channel 4: Local Micro-Partnerships

Priority: medium.

Targets:

- Small trip organizers.
- Camping groups.
- Student clubs.
- Coworking/friend communities.
- Chalet/farm stay hosts who already coordinate group bookings.

Offer:

- "Use Rihla for your next group trip and I will personally help set it up."
- Provide a short Arabic/English message they can forward.

This is not paid influencer marketing yet. It is controlled beta distribution through people who already gather groups.

### Channel 5: SEO Landing Page

Priority: medium.

The root page should become a real landing page:

- H1: `Rihla - split bills with friends in Oman and the GCC`.
- Subhead: no signup, offline, Arabic/English, OMR/GCC-friendly.
- Primary CTA: `Get it on Google Play`.
- Secondary CTA: `Join with an invite code`.
- Sections: trips, roommates, dinners.
- Screenshot or feature graphic.
- Legal/support links stay in footer.
- Add Open Graph/Twitter metadata.
- Add canonical URL.
- Add JSON-LD SoftwareApplication metadata if appropriate.
- Fix Android-only copy until iOS exists.

This helps:

- Invite recipients trust the app.
- Search engines understand the product.
- GitHub homepage can point to a real app page.
- Store listing website/support fields have a stronger destination.

### Channel 6: App Store Optimization

Priority: medium.

Keep the title for now:

`Rihla: Split Bills & Settle Up`

Reason: it is exactly at 30 characters and contains the most important English search terms: split bills and settle up. Changing it before traffic exists risks losing clarity without measurement.

Applied English short description:

Previous:

`Group expense tracker for friends & roommates. See who owes who. Free, offline.`

Current:

`Split group bills, see who owes who, settle up offline - no signup.`

Why:

- Leads with "split group bills".
- Keeps "who owes who".
- Adds "no signup", a true differentiator.
- Avoids leaning on "Free" in the short description.

Alternative variant:

`Split bills with friends. See who owes who. Settle up offline.`

Applied Arabic short description:

`قسّم مصاريف الشلة واعرف من يدين لمن - دون تسجيل ويعمل دون اتصال.`

Screenshot recommendation:

- Screenshot 1 should be "Join from WhatsApp, no signup" or "Split bills with your group in seconds".
- Screenshot 2 can be current persistent balance.
- Screenshot 3 can be split modes.
- Screenshot 4 can be activity/offline/bilingual.

Current screenshots are polished, but they start too advanced. For first-100 conversion, the first screenshot should explain why a friend who just got an invite should install.

## Product Work That Directly Supports Growth

These should be prioritized because they improve acquisition or activation, not because they are general product polish.

1. `#368` - Android deferred invite install referrer.
   - Growth impact: reduces invite-recipient dropoff.
   - Priority: P0 for first 100.

2. `#245` - auto-seed default event and skip hub for single-event groups.
   - Growth impact: makes first expense much faster.
   - Priority: P0/P1 because every champion hits this.

3. Store/landing page SEO refresh.
   - Growth impact: trust and conversion for invite recipients.
   - Priority: P1.

4. In-app review prompt after successful activation.
   - Growth impact: store trust once public/open.
   - Priority: P2, after enough real usage exists.
   - Trigger: after a group has 3 members and a settlement or 2 expenses, not on first launch.

5. Event closeout/shareable recap (`#202`).
   - Growth impact: creates a shareable artifact.
   - Priority: P2 after the first 100 or if a trip group specifically asks for it.

## Measurement Plan

Minimum dashboard for first 100:

- Play installs by day.
- First opens by day.
- Group creates by day.
- Join attempts by day.
- Successful joins by day.
- Invite page visits by code/day.
- Group activation count.
- Activated users count.
- Top dropoff: Play click -> install, install -> open, open -> group, group -> first expense, invite -> join.

Manual tracker is acceptable for the first cohort:

| Champion | Segment | Group use case | Invite sent? | Installs | Joined | Expenses | Feedback |
|---|---|---|---:|---:|---:|---:|---|
| Name | Travel | Salalah trip | no | 0 | 0 | 0 | |

Do not wait for a perfect analytics stack. Use Play Console, Firebase logs where safe, and manual champion reporting.

Privacy rule: do not collect contacts, precise location, or ad identifiers for this milestone. The current privacy positioning is a strength; keep it.

## 30-Day Execution Plan

### Days 1-2: Fix Conversion Surfaces

- Replace Hosting root with a real Android landing page. Done in this pass.
- Add Open Graph metadata. Done in this pass.
- Add a visible Google Play CTA. Done in this pass.
- Fix "iOS and Android" copy while iOS is not launched. Done in this pass.
- Point GitHub homepage to `https://rihla-safar.web.app`.
- Prepare store short-description variants.
- Create 6 shareable screenshots/video clips from the current app.

### Days 3-7: Recruit Champions

- Build the 40-person champion list.
- Classify each as travel, roommates, dinner, coworkers, student/community.
- Send personal asks.
- Add each to closed testing if the app remains closed.
- Get at least 10 groups created in week 1.

### Days 8-14: Activation Push

- Personally follow up with every champion.
- Ask each group to add one real expense.
- Track exact dropoffs.
- Fix blockers immediately if they prevent activation.
- Publish 3 short demo videos: English, Arabic, and bilingual.

### Days 15-21: Improve the Invite Loop

- Ship `#368` if feasible.
- Run first store listing text/screenshot experiment only if traffic is sufficient.
- Update screenshot order to lead with invite/no-signup.
- Ask activated groups for 1 sentence of feedback/testimonial.

### Days 22-30: Expand to Adjacent Groups

- Ask every activated champion for 2 more group intros.
- Target travel/camping/student groups.
- Move from 40 champions to 70 potential champions if the first conversion rate is below target.
- Prepare open testing or production rollout if closed testing is the main bottleneck.

## Success Criteria

By day 30:

- 100 installs from real people.
- 60 activated users.
- 20 activated groups.
- At least 10 groups with 3+ members.
- At least 50 real expenses or settlements recorded.
- At least 10 written feedback notes.
- At least 5 users willing to be contacted again after the beta.

If 100 installs happen but fewer than 10 groups activate, the launch failed. That means acquisition worked but product activation did not.

## Risks

### Risk 1: Closed Testing Friction

If users must be manually added as testers, organic sharing will leak. This is acceptable for a controlled first 100 but not for the next 500.

Mitigation: use a named champion list now, run the opt-in workflow in
`closed-test-access-kit.md` before every install ask, keep real tester emails
outside git, and prepare open testing/production next.

### Risk 2: First Expense Takes Too Long

If users must understand groups, events, ledgers, and roles before adding an expense, champions will drop.

Mitigation: prioritize `#245` and use onboarding messages that tell champions exactly what to do.

### Risk 3: Invite Install Loses Context

Someone taps a group invite, installs from Play, then forgets the code.

Mitigation: ship `#368`; until then, make invite page copy tell users to return to the WhatsApp link after installing.

### Risk 4: Generic ASO Competes Against Stronger Brands

"Split bills" and "expense tracker" are competitive. Rihla will not outrank established apps quickly.

Mitigation: own narrower phrases and local intent: Oman/GCC, OMR, Arabic, no signup, offline, WhatsApp group invite.

### Risk 5: Privacy/Trust Weakness

Money apps need trust. Any unclear website, outdated copy, or missing legal/support page hurts conversion.

Mitigation: keep legal pages visible, update the root page, state no contacts/location/ad ID collection, and show account deletion/support.

## Recommended Next Issues

Create or update tracker issues for:

1. `growth: Android landing page and SEO refresh for rihla-safar.web.app`
2. `growth: Play Store short-description and screenshot-order experiment`
3. `growth: first-100 cohort tracker and champion outreach kit`
4. `growth: prioritize #368 deferred invite capture for 1.7.0`
5. `growth: in-app review prompt after group activation`

Existing related issues:

- `#368` deferred invites - open, 1.7.0.
- `#245` default event / skip single-event hub - open, 1.7.0.
- `#202` event closeout/shareable recap - open, 1.7.0.

## Final Recommendation

Run the first 100 as a controlled cohort, not a public marketing blast.

The operational target is:

- 40 named champions.
- 30 active groups created.
- 100 total users from those groups.
- Activation measured by group joins and real expenses, not installs alone.
- Daily reporting from `dart tool/first_100_summary.dart --today=YYYY-MM-DD`
  so the next action follows the live funnel bottleneck.

The highest-leverage work before outreach:

1. Replace the Hosting root with a real Android acquisition landing page.
2. Prepare a champion outreach kit.
3. Prioritize `#368` so invite installs do not lose their group code.
4. Reorder/test screenshots so the first frame sells "friend invite -> no signup -> split now".

Once that is in place, start outreach immediately. The product is narrow enough and polished enough to get 100 real users through personal group distribution.
