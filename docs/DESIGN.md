# DESIGN.md — Rihla design system

The single source of truth for Rihla's visual language. **The tokens in
`lib/core/theme/tokens/` are the live values; this doc explains the *system* and
the *rules* around them.** When code and this doc disagree, the code's token
values win — fix the doc. When a *screen* and this doc disagree, the screen is
the bug — fix the screen (see [§12 Enforcement](#12-enforcement)).

- **Status:** **Falaj (فَلَج) — Gulf Modern travel ledger**, shipped 2026-07-05
  (#900, PR-1…PR-5). Replaces the Saffron travel-journal direction wholesale:
  new palette (Muscat plaster / night navigation), new type stack (Bricolage
  Grotesque · Zain · Spline Sans Mono), new brand device (the falaj fork),
  dark-pass-tuned. **Both themes are production-tuned** — dark is no longer a
  stub (see [§13 D5/D5a](#13-known-drift--debt)).
- **Authored:** 2026-07-05, from the token source. Values cited are the
  `AppColorTokens.light`/`.dark` instances, `AppTypography` +
  `AppTheme._buildTextTheme`, and `AppMotionTokens.base`.
- **Companion docs:** component API → [SHARED-WIDGETS.md](./SHARED-WIDGETS.md);
  RTL/locale → [LOCALIZATION.md](./LOCALIZATION.md); token wiring →
  [ARCHITECTURE.md § Design System](./ARCHITECTURE.md).

---

## 1. Design language

**Falaj — Gulf Modern travel ledger × premium fintech.** A plaster-and-shale
canvas, a single burnished-brass accent, and upright grotesque type — no
italic anywhere in the system (Bricolage Grotesque bundles no italic cut, and
Arabic typography doesn't mark emphasis that way either). Money is always
monospaced and tabular. The feel is a functional travel ledger — a falaj
irrigation channel, precisely engineered and centuries-trusted — not a
generic Material app, and not the prior era's warm journal-diary read.

**Five principles**

1. **One accent, brass.** Light `#8A5D0D` / dark `#D9A845` is the *only* brand
   color that signals action. Everything else is plaster, shale, and
   hairlines. Resist adding hues.
2. **Upright display, used sparingly.** Bricolage Grotesque carries the
   wordmark, screen titles, and hero numbers — nothing else. Body and UI are
   Zain. Bricolage carries **zero Arabic glyphs**: `displayOf(context, ...)`
   mandatorily reroutes Arabic to Zain upright w700 — never synthesize a
   fallback.
3. **Money is mono and honest.** Every amount renders in Spline Sans Mono with
   tabular figures, palm-emerald positive / pomegranate negative / ink
   neutral. Columns align. OMR shows 3 decimals (baisa).
4. **Tokens over literals.** Color, type, spacing, radius, shadow all come from
   `context.colors|spacing|shadows` + `AppTypography`. A hardcoded hex or font
   size is a defect, not a shortcut.
5. **Directional by default.** Start/end APIs, `DirectionalIcon` for nav
   glyphs — the layout mirrors correctly in Arabic without per-screen
   special-casing.

**Signature moves (brand-defining, not optional):** the **falaj fork** device
— a single channel branching into 3 rivulets — as the wordmark underscore and
the recap-share-card close ritual (**usage law: full fork ≤1 per screen**); the
brass **share-notch tick** as its *only* ambient/unlimited form
(`SectionHeader`'s leading diamond); the **settle-up transfer connector** — the
fork in *structural* `rule2`, never brass (channel-work, not the brand mark, so
N tiles per screen don't count against the fork law; comp-8, #918); a faint
**night star-grid** on dark hero surfaces only; a **polarity caret** (▲/▼)
on the home hero balance; a brass **port-seal** ring on journey tickets
(interim placeholder — 12-glyph redraw is a fast-follow).

---

## 2. Color

Semantic role → token (on `context.colors`) → light hex → dark hex. Use the
**role**, never the hex. `AppColorTokens` field names are historical
(inherited from earthy/teal/saffron iterations) but remapped to Falaj — trust
the role column, not the field name.

**Ground rule: page ground stays G≥R** (a warm/ivory ground reads as an
AI-slop cliché) — `scaffoldBackground` light `#F6F7F5` and dark `#111514` both
hold G≥R by design; don't reintroduce a warm-tinted paper ground.

### Brand & action
| Role | Token | Light | Dark | Notes |
|---|---|---|---|---|
| Primary / brass (buttons, FAB, links, focus) | `primary`, `focusRing`, `focusBorderWarm` | `#8A5D0D` | `#D9A845` | Burnished (light) / lantern (dark) brass |
| Brass-dark (CTA gradient end, text buttons) | `primaryDark` | `#6F4A08` | `#B8862B` | |
| Brass-soft (chip fills, glyph fills) | `saffronSoft` | `#E3E4C9` | `#3A3626` | Field name is historical — cooled off cream on purpose |
| Brass-tint (selected chip/item bg) | `saffronTint`, `selectionFill` | `#F1F2DF` | `#2C2A20` | Tint is never the sole selection signal — always + hairline + tick |

**Ink-on-brass is theme-asymmetric — verify before assuming.** Light CTAs use
white text on brass (`textOnPrimary` `#FFFFFF`, 5.75:1 — brass is dark enough).
Dark CTAs **flip to ink text on brass** (`textOnPrimary` `#1B1F1E`, 7.6:1 —
lantern brass is light enough that white would fail). Don't hardcode white
button text assuming it holds in both themes.

### Surfaces
| Role | Token | Light | Dark |
|---|---|---|---|
| Ground — page/scaffold bg | `scaffoldBackground` | `#F6F7F5` | `#111514` |
| Ground-deep — layered bg | `paperDeep` | `#ECEEE8` | `#0C0F0E` |
| Card — surface | `cardSurface` | `#FFFFFF` | `#1E2422` |
| Card-soft — warm fill (inputs, disabled) | `cardSoft`, `inputFill`, `disabled` | `#F1F2ED` | `#242B28` |

### Ink (text)
| Role | Token | Light | Dark | Note |
|---|---|---|---|---|
| Ink — primary text | `textPrimary` | `#1B1F1E` | `#ECEFEA` | Hajar shale / moonlit plaster (15.5:1 / 14.3:1 on ground) |
| Ink-2 — strong secondary | `ink2` | `#333A38` | `#C9CFC9` | |
| Ink-3 — secondary text | `textSecondary` | `#5C6462` | `#9AA39E` | AA on ground + card (5.7:1 / 6.4:1) |
| Ink-4 — tertiary | `textMuted`, `disabledText` | `#8B918D` | `#6E7773` | **Decorative only — below AA. Never a functional label.** |
| On-brass label | `textOnPrimary` | `#FFFFFF` | `#1B1F1E` | See ink-on-brass note above |

### Lines
| Role | Token | Light | Dark |
|---|---|---|---|
| Border (stone-green hairline) | `border`, `borderWarm`, `rule` | `#E3E6E0` | `#2A322F` |
| Rule-2 — stronger hairline | `rule2` | `#CDD2CA` | `#3A433F` |

> The divider token is named **`rule`**, not `divider`. Field names `border` /
> `borderWarm` / `rule` all resolve to the same value — no functional split.

### Money & status
| Role | Token | Light | Dark | Notes |
|---|---|---|---|---|
| Palm emerald — positive / "owed to you" | `success` / `successText` | `#1F7A5C` / `#175A44` | `#4FBE8F` / `#7FD6AE` | Text ≥7.6:1 both themes |
| Pomegranate — negative / "you owe" | `error` / `errorText` | `#B03A48` / `#8A2430` | `#E0707B` / `#F0A3AB` | Text ≥8.2:1 both themes |
| Warning / offline | `warning`, `offlineBannerBackground` | `#C2410C` | `#E8703A` | **Re-hued off the old amber** (`#F59E0B` collided with brass). `test/unit/theme_contrast_test.dart` enforces hue separation >20° from `primary` (measured ~20.9°/21.5° — a ~1° margin, don't shrink either hue casually) |

**Brass and warning never share one component** — the hue-separation guard
above exists because the *old* saffron/amber pair sat only 9° apart and read
as one color; a new warning-adjacent surface must re-verify against the same
test, not eyeball it.

### Category palette (expense categories)
| | Light | Dark |
|---|---|---|
| `cat1` food (clay tandoor) | `#9C4F2E` | `#D08A63` |
| `cat2` lodging (harbor blue) | `#41708F` | `#7FA9C4` |
| `cat3` transit (night-road indigo) | `#575E93` | `#8E96C9` |
| `cat4` groceries (palm-grove olive) | `#6C7A33` | `#A6B56A` |
| `cat5` activities | `#984B7C` | `#C98BB0` |
| `cat6` other | `#4D5A6A` | `#98A2A8` |

### Gradients
- **Live:** `context.colors.headerGradient` (ink → ink-2, "inside an event"
  module headers) and `context.colors.primaryGradient` (brass → brass-dark,
  CTAs/accent icons).
- The old `AppGradients`/`gradient_tokens.dart` (terracotta/olive/teal/gray,
  archived onboarding) stays **deleted** ([§13 D3](#13-known-drift--debt)).
  Only the two getters above remain.

### Module accents
Only **Ledger** is colored (brass). All other module accents resolve to ink-3
— modules differentiate by **icon, not color**. (Gear/Logistics/Vault/Memories
tokens persist but the features were stripped in Phase 39 — dead; the
`module*Light` fields are additionally orphaned, see
[§13 D7](#13-known-drift--debt).)

---

## 3. Typography

Three families, one Arabic display face. Helpers live on `AppTypography`;
ambient styles come from `Theme.of(context).textTheme.*` (wired to the same
families in `AppTheme._buildTextTheme`). Typography stays **per-script**
(#841): locale-visible display text and translatable captions go through the
context-aware helpers (`displayOf`, `caption`), which re-express the Latin
recipes for Arabic.

| Family | Bundled cuts | Helper | Use |
|---|---|---|---|
| **Bricolage Grotesque** (upright, no italic cut) | 600/700/800 static | `AppTypography.display(...)` / `displayOf(context, ...)` | Wordmark, screen titles, hero numerals. Arabic **mandatorily** reroutes to Zain (Bricolage has zero Arabic glyphs) — never revert that branch. |
| **Zain** (dual-script) | 400/700/800 static | `AppTypography.sans(...)` | All UI text, labels, buttons, body — and user free-text in every locale (never mono). |
| **Spline Sans Mono** (tabular) | 400/500/700 static | `AppTypography.mono(...)` | Money amounts, currency codes, invite codes, dates-as-figures only. Real 400/500/700 — money weights never collapse. |
| *(per-script caption)* | — | `AppTypography.caption(context, ...)` | Small-caps-style captions/eyebrows ("ACTIVE JOURNEYS"). Latin = mono recipe; Arabic = Zain w700, spacing 0, ≥11px (joined script rejects tracking; `.toUpperCase()` is a no-op on Arabic). |
| **Rihla Arabic Display** (Reem Kufi subset) | — | `AppTypography.arabicDisplay(...)` | Arabic wordmark only. A custom square-Kufi commission is the eventual replacement — external, not scheduled (see [§13](#13-known-drift--debt)). |

Fonts are **bundled app assets** (`pubspec.yaml` `flutter: fonts:`), not
fetched at runtime. Tabular figures use `FontFeature.tabularFigures()`
**without** slashed-zero (a slashed 0 reads as Ø on amounts and invite codes,
#148). `display()`/`displayOf()` default `italic: false` and cannot render a
believable italic — no cut is bundled; pass `italic: true` only for a
deliberate one-off synthetic slant.

### w500 mitigation (Zain resolves w500 → w400)

Zain's variable-to-static collapse means a bare `fontWeight: w500` call
renders as w400, **not** a visible medium weight. Per the owner's PR-0 GO
verdict, this was mitigated at **exactly 4 hierarchy-critical dense-list
sites** — compensate via +1sp size and, where the ink wasn't already
`textPrimary`, one ink-step darker (`textSecondary` → `ink2`):
- `ledger_day_card.dart` `_ExpenseRow` title (14→15sp)
- `ledger_day_card.dart` `LedgerSettleRow` recipient name (13.5→14.5sp) + its
  `_Overline` note tail (10.5→11.5sp, `textSecondary`→`ink2`)
- `activity_row.dart` `_GroupChip` (11→12sp, `textSecondary`→`ink2`)

All other `w500` call sites in the app are left byte-identical (no adjacent
hierarchy to collapse against, already resolve to a real bold, or are
Spline/`RAmount` money text with a real 500). Don't "fix" other w500 sites to
match this pattern without re-checking they actually collapse visually first.

### Type scale (`TextTheme`)
| Slot | Family | Size | Weight |
|---|---|---|---|
| `displayLarge` | Bricolage | 44 | 800 |
| `displayMedium` | Bricolage | 36 | 800 |
| `displaySmall` | Bricolage | 28 | 700 |
| `headlineLarge` | Bricolage | 24 | 700 |
| `headlineMedium` | Zain | 20 | 600 |
| `headlineSmall` | Zain | 18 | 600 |
| `titleLarge` | Zain | 17 | 600 |
| `titleMedium` | Zain | 15 | 600 |
| `titleSmall` | Zain | 13 | 600 |
| `bodyLarge` | Zain | 16 | 400 |
| `bodyMedium` | Zain | 14 | 400 |
| `bodySmall` | Zain | 12 | 400 |
| `labelLarge` | Zain | 14 | 600 |
| `labelMedium` | Zain | 12 | 500 |
| `labelSmall` | Zain | 11 | 500 |

Display (Bricolage) slots use `textPrimary`; body slots default to
`textSecondary`. All non-display slots carry tabular figures so inline
numbers stay aligned.

### Text scaling and accessibility

Rihla honors the OS text scale up to **1.5×**. The normal
`MaterialApp.router` `builder` clamps inherited scaling only above that cap,
preserving the platform's scaling behavior below it. Screens must render
overflow-free at 1.5× in both English and Arabic. Money values must never clip
or truncate digits — scale them down to fit.

---

## 4. Spacing & radius

**Unchanged by Falaj** (explicitly out of scope — token *values* here didn't
move, only color/type/brand device did).

### Spacing scale (`context.spacing`)
4 · 8 · 12 · **16 (base grid)** · 20 · 24 · 32 (dp). Use `space4…space32`. Prefer
`SizedBox(height: context.spacing.space16)` over a literal; prefer
`EdgeInsetsDirectional` built from tokens for padding.

### Radius
**Canonical semantic scale (`AppSpacingTokens`, wireframe-aligned):**
`radiusSmall` 8 (chips/tags) · `radiusInput` 14 (inputs, small cards) ·
`radiusCard` 20 (cards, dialogs) · `radiusSheet` 28 (sheets, hero) · `radiusPill`
9999 (buttons, chips, FAB). These equal the radii `AppTheme` renders, so theme and
tokens agree. **Build new UI with the semantic radius for the role** —
`BorderRadius.circular(context.spacing.radiusCard)`, not a literal.

`radiusMedium` (12) / `radiusLarge` (16) are the **legacy scale** — kept for
call sites that predate the semantic radii (~51 as of this rewrite, up from
~19 at v1 — the codebase has grown since; see [§13 D2](#13-known-drift--debt)).
Don't reach for `radiusMedium`/`radiusLarge` in new code.

### Button & touch sizing
Prominent buttons: min `64×52`, padding `(24,14,24,16)` directional, pill shape,
Zain 15/600. Text buttons: min `48×44`. Standard control height: **52dp**
(`buttonHeight`). Never ship a tap target under 44dp.

---

## 5. Elevation & shadow

**Unchanged by Falaj.** Three levels on `context.shadows`. Cards are **flat by
default** (elevation 0 + hairline border or `raised`), not Material-elevated.

| Token | Use | Light spec |
|---|---|---|
| `flat` | Default. Borders do the separating. | `[]` |
| `raised` | Cards lifted off the ground, sticky headers. | gray-900 @ 4% blur10 y4 + @ 2% blur4 y2 |
| `floating` | Modals, FAB, popovers. | gray-900 @ 7% blur24 y8 + @ 3% blur10 y4 |

Shadows are neutral (gray-900 base) at low opacity — soft, never hard
drop-shadows. Dark theme uses a black base at higher opacity (0.35/0.20 raised,
0.50/0.25 floating).

---

## 6. Motion

Canonical tokens on `context.motion` (`AppMotionTokens`). The three base
speeds are **unchanged by Falaj**; two named devices were added.

| Token | Duration | Curve | Use |
|---|---|---|---|
| `motion.quick` | 120ms | `motion.curveStandard` (`easeInOut`) | Tap feedback (`TapBounce` → scale 0.97). |
| `motion.standard` | 200ms | `motion.curveStandard` (`easeInOut`) | Most state transitions, toggles. |
| `motion.emphasis` | 300ms | `motion.curveEmphasis` (`easeOutCubic`) | Banners (`OfflineBanner`), sheets, entrances. |
| `motion.stamp` (`StampMotion`) | 300ms | `easeOutBack` | **Seal-settle**: scale 1.08→1.0, unrotate −3°→0°, one-frame ink bloom (consumer effect). Reduced motion → opacity-only fade, no scale/rotation. **Token-only since #915** — the `StampEntrance` wrapper and its ledger "All square" badge died with the full-chrome ledger; re-add a wrapper when a settled-seal surface returns. |
| `motion.flow` (`FlowMotion`) | 1100ms period | `Curves.linear` (always) | **Continuous channel-fill motion means "syncing" and nothing else, app-wide** — never use for loading/entrance/decorative motion. **Token-only today: no live consumer yet** — the sync indicator is a later wire-up. |

The base three tokens exist; **adoption is the open work** — durations are
still scattered across ~12 ad-hoc `flutter_animate` call sites, migrated onto
`context.motion` in Phase 2 ([§13 D6](#13-known-drift--debt)). Use the tokens
in new code.

Entrance animations (`EmptyStateView`, `flutter_animate` `.animate()`) schedule
tickers — **widget tests landing on empty/error states must `pumpAndSettle()`**
or teardown throws a pending-timer error. Prefer wrapping tappable
cards/icons in `TapBounce` over hand-rolling press scales.

---

## 7. Iconography & RTL

**Unchanged by Falaj** (explicitly out of scope).

- **Icon set:** Iconsax. Use `DirectionalIcon` for any **navigational** glyph
  (arrows, row chevrons) — Iconsax ships without `matchTextDirection`, so nav
  arrows won't mirror in Arabic otherwise. Don't wrap non-directional icons
  (gear, heart, box) — mirroring them looks broken.
- **Directional layout:** `EdgeInsetsDirectional` / `AlignmentDirectional` /
  `Positioned.directional` for all user-facing layout. Never
  `EdgeInsets.only(left:)` or `Alignment.centerLeft`.
- **Amount inputs stay LTR** even in Arabic — force via `Directionality`, not
  `Row.textDirection` (#144/#166). Money displays as ISO code + figure, code-first,
  every locale.
- **The falaj fork mirrors via `Directionality`, not locale** — a UI forced to
  RTL independently of an Arabic locale still fans correctly (`FalajFork`
  reads `Directionality.of(context)`, not `Localizations.localeOf`).

Full rules: [LOCALIZATION.md § RTL](./LOCALIZATION.md).

---

## 8. Money display

`RAmount` is the canonical money widget — never format currency by hand in a
`Text`.

- Spline Sans Mono, tabular, tiered sizing: currency prefix 0.42× · whole part
  1.0× · decimals 0.55×.
- `tone: AmountTone.auto` colors by sign (palm-emerald + / pomegranate − /
  ink 0). Override to `ink` for neutral totals where positive ≠ "good".
- **`polarityCaret` (new, #900 PR-3):** an opt-in leading ▲ (positive) / ▼
  (negative) glyph that encodes owed/owe by **shape**, not color alone
  (colorblind-safe). **Hero surfaces only — leave false on dense rows.**
  Directionally neutral (never mirrors under RTL); no-op at zero. When it
  renders, it becomes the **sole** visual polarity mark — the `+`/`−` sign
  prefix is suppressed so the two marks don't stack. Pass `sign: true`
  alongside it so the spoken `semanticsLabel` still carries the ASCII
  polarity (the caret glyph itself isn't announced). **Wired at exactly one
  site today:** the home balance hero's net `RAmount`
  (`balance_hero_card.dart`) — `recap_share_card`'s hero is total-spent (no
  polarity) and is untouched.
- Decimals are currency-driven: **OMR/KWD/BHD = 3** (baisa), most others = 2,
  JPY = 0. Handled inside `RAmount`/`MoneySerializer` — don't pre-format.
- OMR is the default group currency, not the only live currency. Group create
  chooses a default, expenses can carry their own supported currency, and money
  surfaces must render per-currency buckets with no FX conversion.

---

## 9. Component catalog

Full API in [SHARED-WIDGETS.md](./SHARED-WIDGETS.md). Reach for these before
hand-rolling. The brand-defining ones:

| Widget | Role |
|---|---|
| `RAmount` | Canonical money display, incl. hero `polarityCaret` (see §8). |
| `RAvatar` / `RAvatarStack` | Person initials stamp, stable per-name color (retinted 8-slot set). **One stable color per person, everywhere — never override `hue` for identity** (DEC-3 / #149). |
| `FalajFork` / `FalajForkPainter` | The brand device — channel branching into 3 rivulets. Mirrors via `Directionality`. **Usage law: full instance ≤1 per screen** — ships in `WordmarkLogo`'s underscore and `recap_share_card`'s close-ritual footer. |
| `WordmarkLogo` | Upright Bricolage Grotesque "Rihla" (ReemKufi "رحلة" in Arabic) + brass `FalajFork` underscore. |
| `CoverArt` | Procedural ticket-card scenery (no photo assets) — 5 `EventType`-mapped palettes, re-dressed for Falaj. |
| `SectionHeader` | Per-script caption label + leading brass **share-notch tick** (the fork's only *ambient*, unlimited-use form) + optional "See all". |
| `StarGridPainter` | Faint deterministic dot-grid on **dark hero surfaces only** (`kStarGridOpacity` = 0.03), clipped to the card radius. Replaces the retired `GrainOverlay` — light theme has **no** grain/texture anymore. |
| `ModuleHeader` | Dark-gradient module header (back, title, subtitle, actions). |
| `EmptyStateView` | Icon + title + message + optional CTA for empty/error. |
| `LoadingButton` | 52dp pill button with spinner state. |
| `SkeletonLoader` | Layout-matched shimmer placeholders. |
| `OfflineBanner` | Self-managing, icon-led connectivity strip (icon+text carry the warning color — never brass, see §2). |
| `TapBounce` | Press-scale feedback wrapper (120ms / 0.97). |
| `DirectionalIcon` | RTL-mirroring nav glyph wrapper. |

**Removed:** `GrainOverlay` (light paper-grain texture) — fully deleted, no light-theme replacement.

**Promote to `shared/` when:** used in 2+ features · single nameable
responsibility · reads tokens not literals · testable in isolation. Otherwise keep
it in the feature dir until a second feature copies it.

---

## 10. Screen patterns

The canonical screen skeleton:

```
Scaffold (scaffoldBackground = ground)
 └─ body: Column
     ├─ OfflineBanner()              // self-managing, top of body
     ├─ ModuleHeader(...)            // inner screens; or wordmark top-bar on Home
     └─ content (ListView / CustomScrollView)
         ├─ SectionHeader('UPPERCASE LABEL')   // brass tick + per-script caption
         ├─ cards / rows (flat card + hairline, or raised)
         └─ EmptyStateView(...)      // when the list is empty
```

- **App bar:** transparent, elevation 0, centered. Inner screens show a large
  upright Bricolage-Grotesque title; Home shows the wordmark (avatar left ·
  wordmark center · bell right).
- **Cards:** `cardSurface`, radius per §4, `flat`+hairline or `raised`. Pad
  with `space16`.
- **List rows:** leading `RAvatar`/icon · title (`titleMedium`) + subtitle
  (`bodySmall`/mono date) · trailing `RAmount` or `DirectionalIcon` chevron.
- **States — every async surface needs all four:** loading (`SkeletonLoader`
  matching the layout) · empty (`EmptyStateView`) · error (`EmptyStateView` variant)
  · content. Don't ship a spinner-only or a bare error string.
- **Top-level direct-entry screens guard back:** `if (!context.canPop()) go('/home')`.
  Nested sub-routes don't need it (GoRouter materializes ancestors). See
  CLAUDE.md § Routing landmines before touching this.
- **Journey ticket:** perforated tear-line stub (KEEP-6) + `CoverArt` band +
  brass **port-seal** ring in the content stub's outer corner — an interim
  placeholder for the 12 trip-stamp glyphs, not the `FalajFork` device (see
  [§13](#13-known-drift--debt)).

---

## 11. Voice & copy

- Section labels: UPPERCASE, per-script caption (`AppTypography.caption`) —
  Latin mono recipe, Arabic Zain w700 no tracking, ~1.2 letter-spacing
  (Latin only; joined Arabic script rejects tracking).
- Sentence case for titles, buttons, body. No Title Case On Everything.
- Currency: ISO code + figure ("OMR 10.500"), code-first, all locales.
- Localize every user-facing string via `context.l10n` — no literals in widgets.
  Arabic emits Western digits via `intl 'ar'` (known; see notation memory).
- Document-close ritual: share cards/receipts end with the fork underscore +
  "recorded in Rihla" / "مُسجَّل في رِحلة" (`recapRecordedInRihla`) beneath the
  footer row — the PDF trip receipt gets the caption only (no `CustomPaint`
  fork on the `pdf` package's canvas).

---

## 12. Enforcement

What keeps the system unified, split by teeth:

**CI-gated (build fails):**
- **Theme purity check** (`tool/check_theme_purity.sh`) — **this is the color
  lint.** Run only in CI (`readiness_check.yml` "Theme purity check"), **not**
  by `flutter analyze` or `flutter test` — a violation passes every local
  check and only goes red in CI. Forbids: a hardcoded `Color(0x…)` outside
  `lib/core/theme/tokens/` without a `// design-token-justified:` comment
  within 5 lines above; a `.textMuted` read without a
  `// textMuted-decorative-justified:` comment; any direct
  `AppColorTokens.light.*`/`AppShadowTokens.standard.*` access. Run it
  locally before pushing any new/changed widget.
- **WCAG contrast + brass/warning hue separation** —
  `test/unit/theme_contrast_test.dart` asserts every ink/status pair ≥4.5:1
  in both themes and a >20° hue gap between `warning` and `primary`; part of
  the normal `flutter test` run.
- 80% line coverage; `flutter analyze` clean; `prefer_const_constructors`.
- Goldens (`test/goldens/`, **macOS-only**, CI-excluded) — regenerate and
  eyeball-review on macOS after any visual change; includes the RTL-capable
  `painter_golden_harness.dart` used for `FalajFork`.

**Convention (reviewer-enforced — the token-adoption gap):**
- Spacing/radius via `context.spacing` + token radii, not literals.
- Text via `AppTypography.*` / `textTheme.*`, not raw `TextStyle(fontSize:…)`.
- Directional APIs + `DirectionalIcon` (greps in `tool/check_release_readiness.sh`).
- Shared widgets before custom; `RAmount` for money; `RAvatar` for people;
  `FalajFork` capped at ≤1 full instance per screen (usage law, not CI-checked).

**Adding a token:** add the field to the relevant `tokens/*.dart` (+ `copyWith` +
`lerp`), wire it into both `light` and `dark` instances, and — for a one-off
gradient/literal that genuinely can't be a token — annotate
`// design-token-justified: <reason>` so the lint allows it.

**Adding/removing UI:** when you remove an element, grep tests for its label/key
and delete obsolete assertions (don't patch them).

---

## 13. Known drift & debt

Honest current state (2026-07-05) — the gap between "system" and "adherence".
Counts re-run against the live tree; the codebase has grown substantially
since the 2026-06-06 baseline (172 → 266 `lib/` files) on top of the Falaj
program itself, so raw counts moved even where the underlying debt didn't.

| # | Drift | Evidence | Action |
|---|---|---|---|
| D1 | **Token adoption ~43%.** ~151 `lib` files hardcode spacing/radius/text. | 115/266 files use `context.*`; 230 literal `SizedBox(...: <num>)`, 166 literal `BorderRadius.circular(<num>)`, 28 raw `TextStyle(` outside `AppTypography` (post-#932 sweep; the 28 are justified partial-overrides / 1 italic / 2 RichText-root spans / 1 `leadingDistribution` no helper expresses). | Phased per-feature refactor → tokens/primitives continues. Re-run these greps to track — the counts, not the doc, are the metric. |
| D2 | **Radius — semantic tokens landed; call sites pending.** Canonical `radiusInput/Card/Sheet/Pill` match `AppTheme`; ~51 legacy `radiusMedium`/`radiusLarge` call sites not yet migrated (grew from ~19 as the app added surfaces). | §4. | ✅ Phase 1 (tokens). Phase 2: migrate call sites per screen. |
| D3 | **`AppGradients` deleted.** ✅ terracotta/olive/teal/gray + `AppGradientPair` + the `context.gradient()` helper removed (zero live callers). | — | ✅ Done. |
| D4 | **Group avatar dead code deleted.** ✅ `AppGroupAvatarColors` + `groupAvatarSlot()` + `_stableGroupHash` removed (zero live callers; groups render via `RAvatar`). | — | ✅ Done. |
| D5 | **✅ Resolved (#900 PR-4, #913).** Dark theme is now tuned night-navigation: card surface lifted to `#1E2422` for tint-based elevation, all five component themes light already had (chip/divider/bottomSheet/dialog/FAB) ported to dark tokens, input hints moved off `textMuted` (~3.1:1) onto `textSecondary` (~5.6:1). | `color_tokens.dart` dark instance; `app_theme.dart` `_buildDarkTheme`. | Done. |
| D5a | **✅ Resolved (#900 PR-4, #913).** App now defaults to `AppThemeMode.system` again (was pinned to `light` since #818/2026-07-03 while D5's dark pass was a stub). | `AppSettings.themeMode` default + `SettingsService.loadSettings` fallbacks. | Done. |
| D6 | **Motion tokens landed; adoption pending.** `context.motion` (quick/standard/emphasis + curves, plus the new `stamp`/`flow` devices) exists; ~12 ad-hoc `flutter_animate` duration literals not yet migrated. `flow` additionally has **no consumer at all yet** — reserved for a future sync indicator. | §6. | ✅ Phase 1 (tokens). Phase 2: migrate ad-hoc durations; wire `flow` when the sync indicator ships. |
| D7 | **Still orphaned.** `moduleLedgerLight`/`moduleGearLight`/etc. have **zero `lib/` readers** (defined only in `color_tokens.dart`); `event_type_picker_screen.dart`, their last reader, stays deleted. | grep: `colors.module*Light` → 0 hits outside `color_tokens.dart`. | Delete the dead `module*Light` token fields in a cleanup PR. |
| D8 | **✅ Resolved (comp-8, #918).** Owner decided 2026-07-05: the connector is the falaj fork in **structural `rule2`, never brass** — channel-work, not the brand mark, so N tiles/screen don't breach the ≤1-full-fork law. `FalajForkPainter` replaced the dashed `_TransferRailPainter` in `group_settlement_tile.dart`; the rail's trailing arrow retired with it (the branch fan is the direction cue, Directionality-mirrored). | `group_settlement_tile.dart`; RTL + non-brass pins in `group_settlement_tile_test.dart`. | Done. |
| D9 | **#915 open — unrouted full-chrome event module screens pending deletion.** PR-5 consolidated routes into `EventCommandCenter` `?tab=` redirects but *kept* the `embedded:false` full-chrome branches of `LedgerScreen`/`ActivityFeedScreen` (unreachable) because ~12 `test/features/ledger/*` + `activity_feed_screen_test.dart` construct them directly. | Issue #915. | Delete the unreachable branches + migrate/retire their tests. `EventRecapScreen`/`SettleUpScreen` are real routed screens, not part of this cleanup. |
| D10 | **#916 open — stale hero hint copy.** `BalanceHeroCard`'s `homeBalanceHeroHint` ("See your journeys") + down-arrow cue still describe the pre-PR-5 scroll-to-journeys behavior; PR-5 rewired the tap to the per-group breakdown sheet and left copy untouched per its "no other copy changes" scope rule. | Issue #916. | Re-copy the EN+AR hint pair + swap the cue, one-sentence-diff, no Gate needed. |
| D11 | **Port-seal SVG redraw — optional fast-follow, not started.** The journey ticket's brass corner seal is a plain ring placeholder (`_BrassSeal` in `journey_ticket_card.dart`), not a redraw of the 12 trip-stamp glyphs as brass seals. | `journey_ticket_card.dart` `_BrassSeal`. | Optional; the 12 glyph ids + monogram fallback are unaffected either way — see CLAUDE.md trip-stamp glyph invariant. |
| D12 | **Custom square-Kufi wordmark — external, unscheduled.** The Arabic wordmark still renders via the Reem Kufi subset (`Rihla Arabic Display`); a bespoke square-Kufi lockup was named as the eventual replacement but is an external commission with no date. | §3. | No action until commissioned — don't treat the Reem Kufi subset as a stopgap needing an internal fix. |

---

## 14. Protected invariants — do NOT break (KEEP list)

Strengths the design review flagged as worth protecting. Treat these as
regression guardrails: any PR that would change one needs an **explicit
decision** (call it out in the PR body), not a silent edit. Falaj's KEEP
decisions (from `docs/plans/2026-07-05-falaj-rebrand.md`) are folded in below —
three prior KEEPs were explicitly broken by the rebrand, the rest hold.

- **KEEP-1 — Type system: BROKEN BY FALAJ, replaced.** The italic-serif +
  mono-label + sans-body system is retired. Replacement: upright Bricolage
  Grotesque display + Zain UI/body (dual-script) + Spline Sans Mono money —
  no italic anywhere (§3).
- **KEEP-2 — Palette + semantics: BROKEN BY FALAJ, replaced.** Warm
  saffron/sage/rust tones are retired. Replacement: brass primary, palm
  emerald positive, pomegranate negative — the positive/negative *semantic*
  mapping (green=owed, red=owe) is the part that survived; the hues did not
  (§2).
- **KEEP-3 — Settle-Up transfer connector** — clear who-pays-whom. The
  *clarity* is the invariant; the material was re-dressed by comp-8 (#918):
  structural `rule2` falaj fork whose branch fan points into the payee and
  mirrors under RTL (§13 D8).
- **KEEP-4 — RTL build:** logo lockup, mirroring, localized strings (§7).
- **KEEP-5 — Copy voice:** "everyone's even" / "الجميع متوازن"
  (`settleUpEveryoneEvenHeadline`; the ledger's "All square." / "كل شيء
  متوازن" pair was retired with the full-chrome hero in #915 — the event's
  settled voice now lives in the hub's balance block. Don't splice surviving
  pairs) (§11).
- **KEEP-6 — Ticket / boarding-pass trip cards:** perforated tear-line, side
  notches, per-trip `CoverArt`. Re-dressed in plaster/shale/brass materials,
  structure unchanged — protect and extend.
- **KEEP-7 — "Expense saved · synced with cloud" modal** — offline-first
  feedback.
- **KEEP-8 — Light theme execution: BROKEN BY FALAJ, replaced.** The
  cream/white card hierarchy is retired in favor of the plaster/white Falaj
  hierarchy (§2, §5) — dark is now equally production-tuned, not a
  light-only priority.
- **DEC-3 (shipped invariant):** one deterministic avatar colour per user via
  `RAvatar._stableHash(name)` → 8 slots (retinted for Falaj, same mechanism);
  callsites pass **name only**, never override the hue. Keep deterministic.
  (Cross-ref: #490 consolidation must not reintroduce per-site avatar tints.)
- **KEEP-9 (new, Falaj-native) — fork usage law:** full `FalajFork` device
  ≤1 per screen, the `SectionHeader` share-notch tick is the only uncapped
  ambient form (§1, §9, §12). **Flow-motion means syncing, nothing else**
  (§6). **Brass and warning never share one component** (§2).
