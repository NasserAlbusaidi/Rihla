# Claude Design — Ledger Screen (V1 brief)

Design **multiple variations** of the **Ledger Screen** for **Rihla**, a Flutter mobile app for group/event expense-splitting (Splitwise-like, but organised around persistent groups and events inside them).

The current screen works but feels generic. I want to explore strong visual + UX directions that lean into the "saffron travel-journal" identity. Generate **3-4 distinct variations** — different structural takes, not just colour swaps.

---

## Screen role

The Ledger is the **event-scoped expense + settlement log** — the showpiece of every event. Users land here from the Event Command Center hub. It must answer, in order:

1. **Where do I stand in this event?** (am I owed, or do I owe — and how much)
2. **What recent activity is there?** (expenses + settlements, chronologically)
3. **What can I do next?** (add expense, settle up, see specific person)

It is opened often — fast scanning matters more than data density.

---

## Constraints

- **Width:** ~390px (iPhone 14/15 width). All variations must fit this.
- **WCAG AA contrast** on every functional label (amounts, payer names, dates, CTAs). Decorative-only colors may go softer.
- **Touch targets:** 48dp minimum for every tappable row/button.
- **No bottom nav** on this screen — it's a sub-route from event hub.
- **Must support:** OMR (3-decimal currency, e.g. `OMR 12.345`), settlements as inline timeline items distinguishable from expenses, soft-delete absence (deleted rows are filtered out before this screen sees them).
- **States to design:** loaded (5+ expenses), empty (zero expenses), settled (you owe / are owed 0), error/offline.

---

## Palette — saffron travel-journal direction

Use **only** these tokens. No off-palette colours.

| Token | Hex | Use |
|---|---|---|
| **paper** (scaffold) | `#F6F1E6` | page background |
| **paperDeep** | `#EFE8D7` | layered surface tone |
| **cardSurface** | `#FFFFFF` | card fills |
| **cardSoft** | `#FBF7EE` | input/secondary card fills |
| **saffron (primary)** | `#D17B2C` | primary CTA, active accent, ledger module accent |
| **saffronDark** | `#B5641A` | saffron CTA gradient pair |
| **saffronSoft** | `#F4DDB8` | saffron chip backgrounds |
| **saffronTint** | `#FBEED5` | selected-chip background, soft saffron fill |
| **sage (success)** | `#5C7A57` | "owed to you" / positive amounts |
| **sageText** | `#3F5A3B` | WCAG-safe positive text |
| **rust (error)** | `#A84B33` | "you owe" / negative amounts |
| **rustText** | `#7A2F1F` | WCAG-safe negative text |
| **ink** (textPrimary) | `#1B1A17` | primary text, dark CTAs |
| **ink2** | `#3D3A33` | dark gradient pair |
| **ink3** (textSecondary) | `#6B675D` | secondary text |
| **ink4** (textMuted) | `#948F82` | DECORATIVE ONLY — below AA, never for functional labels |
| **rule** | `#EAE5D9` | 8% ink hairline divider |
| **rule2** | `#D9D3C5` | 14% ink hairline |

**Category palette** (for category dots/icons only — these are stable, theme-locked):

| Category | Hex | Token |
|---|---|---|
| food | `#C2693B` | cat1 |
| lodging | `#4F7B96` | cat2 |
| transit | `#8C6A2F` | cat3 |
| groceries | `#6F7A3A` | cat4 |
| activities | `#94517A` | cat5 |
| other | `#4D5A6A` | cat6 |

---

## Spacing scale

Use **only** these values: `4, 8, 12, 16, 20, 24, 32`. Border radii: `8` (small/chip), `12` (medium/button), `16` (large/card), `24` (hero card). Standard button height: 48dp.

---

## Typography

Three fonts, no others:

- **Geist** (sans, system-feel) — body text, labels, captions
- **Geist Mono** (tabular figures) — all money, time/date stamps, monospace overlines (`UPPERCASE · LETTERSPACED`)
- **Instrument Serif** *italic* — display headlines, day-section labels, hero phrases ("Your tally on this trip", "All settled")

Tabular numbers (Geist Mono) for **every** money display so columns align.

---

## Data on the screen (real model)

- **Event title** (e.g. "Muscat weekend trip", italic display)
- **Event meta**: date range ("May 5 — May 8") + participant count ("4 PEOPLE"), uppercase Geist Mono overline
- **Event cover art** — procedural ticket-stub illustration (`CoverArt.forEventType`) — 120-220px hero band depending on direction
- **Current user net balance** in OMR (3 decimals) — signed: `+12.450` (sage, you're owed) or `-7.200` (rust, you owe) or `0` (settled, ink)
- **Per-person breakdown** of who owes you / you owe (3-5 people typical, can be 10+). Each row: avatar (22-28px circle with initials, deterministic slot color) + name + signed amount + relative magnitude (bar/dot/ring — designer's call).
- **Event total** — sum of all expenses (e.g. "trip total · OMR 142.350")
- **Category filter chips** — All · N, then chips per present category (Food, Lodging, Transit, Groceries, Activities, Other) with the cat-color dot
- **Timeline items** — expenses and settlements interleaved, chronological (newest first), grouped by day
  - **Expense row:** category icon · description ("Dinner at Bait Al Luban") · "Nasser paid · split 4 ways" · `OMR 24.000` (total) + signed sub-amount `−6.000` (this user's share)
  - **Settlement row:** different visual treatment — arrow icon · "Nasser paid Aya" · `OMR 7.500` — these are append-only debt-clearing transfers
- **Day-section header** — "Today · May 14", "Yesterday · May 13", "May 12" (Instrument Serif italic, 18-22pt)
- **Primary CTAs**: `+ Add expense` (saffron-filled or ink-filled) and `Settle up` (secondary)
- **Footer:** mono "· END OF LEDGER ·"

---

## Existing shared widget vocabulary (re-use, don't reinvent)

- **CoverArt** — procedural ticket-stub illustration with event-type-specific glyphs
- **RAmount** — money rendering with tabular figures, optional sign, sage/rust/ink tone
- **RAvatar** — initials circle with stable per-id slot color
- **OfflineBanner** — amber strip when offline
- **Iconsax** icon set (already in app)

Categories already map to existing icons: food → coffee, lodging → house, transit → car, groceries → cart, activities → star, other → box.

---

## Variations to explore (give me 3-4 distinct directions)

Aim for **structural** difference, not just chrome. Suggested axes:

1. **Hero treatment** — full-card hero with bars vs. minimal stacked numbers vs. statement-style ("You're up 12.450 across 4 settle-ups") vs. visual sparkline of accumulated balance over time.
2. **Person breakdown placement** — inside hero card (current) vs. dedicated horizontal scroll strip (V5R-style roster dots/chips) vs. expandable section vs. hidden behind "see breakdown" CTA.
3. **Category filter affordance** — chip strip (current) vs. segmented control vs. icon-only filter row vs. fold into header dropdown.
4. **Timeline visual** — day-grouped cards (current) vs. continuous list with sticky day headers vs. condensed compact rows vs. magazine-style layout with bigger spacing.
5. **Settlement visual** — distinct row variant (current) vs. inline pill between expense rows vs. dedicated "Settled" section vs. background-tinted row.
6. **Quick actions** — bottom CTA strip vs. floating "+" FAB vs. swipe-to-settle on person rows vs. sticky add-expense composer at bottom.

Pick directions that feel like a **travel journal** — handcrafted, paper, calm — not a fintech dashboard. Use Instrument Serif italic boldly for the hero number or section labels; keep mono small and deliberate for overlines + money; use cardSoft and paperDeep as layering tones rather than relying only on shadows.

---

## Deliverables

Per variation:
- Loaded state (5+ expenses, mixed categories, 1-2 settlements)
- Empty state (zero expenses)
- "All settled" state (balance = 0 with expenses present)
- Annotate any direction-specific motion (e.g. hero collapses on scroll)

Generate side-by-side HTML/JSX I can compare. Don't ship code — these are design oracles for a Flutter implementation downstream.
