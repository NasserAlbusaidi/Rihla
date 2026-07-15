# Passive-acquisition audit — 2026-07-15

Three-agent research sweep (search-intent EN+AR · on-page SEO audit of the live
site · off-site channel scan), run the day the Falaj feature graphic + invite
og-cards shipped (#1260/#1261/#1262). Everything below was **evidence-checked at
run time**; re-verify before acting on it months later.

## Headline findings

1. **The site was (as of this audit) likely not indexed at all.**
   `site:rihla-safar.web.app` and even the exact domain string returned zero
   results. Strongest hypothesis: Search Console property never
   verified / sitemap never submitted. Until that's done every SEO item below
   is moot. *Owner action, ~5 min:* verify the property (HTML-file or meta-tag
   method — no DNS control on web.app), submit `sitemap.xml`, Request Indexing
   on the 8 pages. Community threads also document `*.web.app` sites as a
   recurring non-indexing/sitemap-fetch-failure pattern — indexing must be
   *confirmed*, not assumed. A marketing-only custom domain (deep-link host
   stays `rihla-safar.web.app` forever — #130) is the eventual fix if web.app
   refuses to rank; decision deferred.

2. **Brand collision: "Rihla" is a contested name.** `rihla-app.com` — "Rihla:
   AI Travel Planner for Groups" — is live on both stores, GCC-targeted (cites
   Wadi Shab), bilingual RTL, **with its own expense-splitting feature ("the
   Kitty")**. Plus ≥4 more Rihla-named apps (Karwa taxi, UAE fitness, parental
   monitoring, Oman travel companion). Branded queries surface them, not us.
   Mitigations shipped: `sameAs` → Play listing in the JSON-LD (#1262).
   **Open decision:** consistent disambiguating tagline everywhere vs leaning
   on a qualifier. Branded SEO compounds slower until decided.

3. **Splitwise has zero Arabic support — confirmed on their own feedback
   forum**, with a team statement it isn't coming soon. This is the defensible
   anchor claim for Arabic comparison content.

## Verified keyword gaps (Arabic-first is the wedge)

| Query family | State of the SERP | Play |
|---|---|---|
| بديل Splitwise (عربي) | English listicles only; **no Arabic-native comparison content exists** | "بديل Splitwise" page (ar + en mirror) anchored on finding 3 |
| مصاريف السكن المشترك (roommates) | **Zero** splitting apps — only roommate-finder platforms + housing-license pages | Dedicated ar page; maps to persistent groups + OMR |
| تطبيق مصاريف الشلة (colloquial) | Generic personal-budget trackers only | Cheap colloquial-tone page/post |
| "split bills app Oman" (en) | No splitting competitors — but SERP is utility-bill **payment** apps (Khedmah/ONEIC/Omantel) | Keep, but copy must say *group expenses* to dodge the bill-pay intent |
| "splitwise alternative" (en) | Saturated (Tricount/Splid/Settle Up + competitor-run listicles); Spliteroo already owns the Saudi-English angle | Don't chase head term; Oman/GCC-framed long-tail only |
| من يدين لمن | Noisy (mixes fatwa content) | Supporting copy only, never a page anchor |

**Competitors worth knowing:** فكفكها / fakfekha.com (Arabic-native trip splitter,
organically ranks for تقسيم مصاريف الرحلة — feature-diff before writing any
comparison page); HessaPay (Kuwait, funded, "Split the bill, GCC style",
payments-leaning). Splitwise 2026 free-tier backlash (3 expenses/day cap, ads,
$4.99/mo Pro) is actively refreshing the alternatives genre — good timing.

## On-page state after #1262

Shipped in #1262: privacy/terms stale "group trip planning" descriptions fixed,
index description ≤155 chars, "Splitwise Alternative / بديل Splitwise" into the
split-bills-oman titles, `sameAs`, self-canonicals on the 4 utility pages,
sitemap `lastmod`. Remaining, deliberately deferred:

- **Arabic parity for help/privacy/terms/delete-data** (4 of 8 sitemapped pages
  are EN-only on a bilingual-first site; ar footers link them with Arabic
  anchor text and no lang cue). Real localization effort — needs a decision.
- **Render-blocking Google Fonts** on all 4 marketing pages (3-hop waterfall;
  AR stack is 26 @font-face declarations vs 18 EN). Fix: preload+swap or
  self-host WOFF2s. Medium effort.
- Cache-control 1h on static assets (Firebase default; minor).
- **FAQPage rich results are dead on Google since 2026-05-07** (the existing
  FAQ JSON-LD is Bing/DuckDuckGo/AI-crawler-only now — keep, don't extend for
  Google). HowTo likewise curtailed since 2023. Don't add `aggregateRating`
  until a real, page-displayed rating exists.

## Off-site one-timers (ranked; honest-disclosure only)

1. **AlternativeTo** (`alternativeto.net/manage/new/`) — durable
   "alternative to Splitwise/Tricount" browse surface, ~15 min.
2. **atheer.om pitch** — Omani outlet with a confirmed Sept-2024
   finance-app-roundup precedent (listed المصاريف alongside EN apps). Arabic
   pitch, "Omani-built, OMR-native, works offline". info@atheergroup.om, ~30 min.
3. **Product Hunt** — one-time spike + permanent badge/backlink; ~2-3h prep,
   launch Tue–Thu.
4. **AITnews / Arageek** (pan-Arab tech blogs; editorial@aitnews.com) — reuse
   the atheer pitch.
5. **One "I built this" post** in r/oman (or r/androidapps/r/SideProject) —
   re-check the sub's self-promo rules live first (couldn't fetch them
   in-session).
6. SaaSHub (~10 min, name Splitwise/Tricount in "alternative to"), Gartner
   trio (Capterra/GetApp — B2B mismatch, backlink only).
7. **Skip, confirmed:** F-Droid (Firebase stack disqualifies under their own
   inclusion policy), Slant (crowd-edited, not submission-driven), Zapier (no
   integration surface), Aptoide/Uptodown mirrors (no controlled listing,
   stale-build reputational risk), cold pitches to PCMag/MakeUseOf/etc. (no
   live Splitwise-alternatives piece found to pitch into).

## Engineering levers

- **In-app review prompt confirmed absent** (`in_app_review` — zero matches in
  `lib/`/pubspec). Ratings feed both Play ranking and listing conversion;
  Google guidance: trigger contextually after a meaningful action (e.g. a
  settle-up completing), quota ~1 successful prompt per device per 1–2 weeks.
  Filed as a follow-up issue.
- Play Console **category assignment** isn't fastlane-managed and couldn't be
  verified from the repo — check once in the console (feeds "similar apps").

## Evidence caveats (recorded on purpose)

ASO lift percentages circulating in search results are content-farm lore, not
primary-sourced. Reddit rules were unfetchable in-session. Arabic Google
autocomplete could not be reliably scraped (one pull returned garbled
off-language content) — the Arabic gap findings rest on organic-SERP absence,
which held consistently, not on volume numbers.
