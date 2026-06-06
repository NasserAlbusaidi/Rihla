# DESIGN.md — Rihla design system

The single source of truth for Rihla's visual language. **The tokens in
`lib/core/theme/tokens/` are the live values; this doc explains the *system* and
the *rules* around them.** When code and this doc disagree, the code's token
values win — fix the doc. When a *screen* and this doc disagree, the screen is
the bug — fix the screen (see [§12 Enforcement](#12-enforcement)).

- **Status:** Saffron travel-journal direction, locked 2026-05-10. Light theme is
  production-tuned; **dark theme is a compiling-but-untuned stub** (see [§13](#13-known-drift--debt)).
- **Authored:** 2026-06-06, from the token source. Values cited are the
  `AppColorTokens.light` instance.
- **Companion docs:** component API → [SHARED-WIDGETS.md](./SHARED-WIDGETS.md);
  RTL/locale → [LOCALIZATION.md](./LOCALIZATION.md); token wiring →
  [ARCHITECTURE.md § Design System](./ARCHITECTURE.md).

---

## 1. Design language

**Saffron travel-journal × premium fintech.** A warm paper canvas, ink text, a
single saffron accent, and serif italic for emotional/identity moments. Money is
always monospaced and tabular. The feel is a hand-kept travel journal that
happens to do precise accounting — not a generic Material app.

**Five principles**

1. **One accent.** Saffron `#D17B2C` is the *only* brand color that signals
   action. Everything else is paper, ink, and hairlines. Resist adding hues.
2. **Serif italic is the voice, used sparingly.** Instrument Serif italic carries
   the wordmark, screen titles, and hero numbers — nothing else. Body and UI are
   Geist sans.
3. **Money is mono and honest.** Every amount renders in Geist Mono with tabular
   figures, sage for positive / rust for negative / ink for neutral. Columns
   align. OMR shows 3 decimals (baisa).
4. **Tokens over literals.** Color, type, spacing, radius, shadow all come from
   `context.colors|spacing|shadows` + `AppTypography`. A hardcoded hex or font
   size is a defect, not a shortcut.
5. **Directional by default.** Start/end APIs, `DirectionalIcon` for nav glyphs —
   the layout mirrors correctly in Arabic without per-screen special-casing.

**Signature moves (brand-defining, not optional):** italic "Rihla" wordmark with
a saffron underline flourish · perforated ticket-stub journey cards with a
procedural `CoverArt` band · sage/rust tonal split on the hero balance · tiny
uppercase mono section labels · paper-grain texture on hero surfaces.

---

## 2. Color

Semantic role → token (on `context.colors`) → light hex. Use the **role**, never
the hex. `AppColorTokens` field names are historical (inherited from the earthy/teal
iterations) but remapped to saffron — trust the role column, not the field name.

### Brand & action
| Role | Token | Hex |
|---|---|---|
| Primary / saffron (buttons, FAB, links, focus) | `primary`, `focusRing`, `focusBorderWarm` | `#D17B2C` |
| Saffron-dark (CTA gradient end, text buttons) | `primaryDark` | `#B5641A` |
| Saffron-soft (chip fills, glyph fills) | `saffronSoft` | `#F4DDB8` |
| Saffron-tint (selected chip/item bg) | `saffronTint`, `selectionFill` | `#FBEED5` |

### Surfaces
| Role | Token | Hex |
|---|---|---|
| Paper — page/scaffold bg | `scaffoldBackground` | `#F6F1E6` |
| Paper-deep — layered bg | `paperDeep` | `#EFE8D7` |
| Card — white surface | `cardSurface` | `#FFFFFF` |
| Card-soft — warm white (inputs, disabled) | `cardSoft`, `inputFill`, `disabled` | `#FBF7EE` |

### Ink (text)
| Role | Token | Hex | Note |
|---|---|---|---|
| Ink — primary text | `textPrimary` | `#1B1A17` | |
| Ink-2 — strong secondary | `ink2` | `#3D3A33` | |
| Ink-3 — secondary text | `textSecondary` | `#6B675D` | AA on paper |
| Ink-4 — tertiary | `textMuted`, `disabledText` | `#948F82` | **Decorative only — below AA. Never a functional label.** |
| On-saffron label | `textOnPrimary` | `#FFFFFF` | |

### Lines
| Role | Token | Hex |
|---|---|---|
| Border (8% ink) | `border`, `borderWarm` | `#EAE5D9` |
| Rule — hairline divider | `rule` | `#EAE5D9` |
| Rule-2 — stronger hairline (14% ink) | `rule2` | `#D9D3C5` |

> The divider token is named **`rule`**, not `divider`.

### Money & status
| Role | Token | Hex |
|---|---|---|
| Sage — positive / "owed to you" surface | `success` | `#5C7A57` |
| Sage-dark — positive text (AA) | `successText` | `#3F5A3B` |
| Rust — negative / "you owe" surface | `error` | `#A84B33` |
| Rust-dark — negative text (AA) | `errorText` | `#7A2F1F` |
| Amber — warning / offline | `warning`, `offlineBannerBackground` | `#F59E0B` |

### Category palette (expense categories — muted journal stamps)
`cat1` food `#C2693B` · `cat2` lodging `#4F7B96` · `cat3` transit `#8C6A2F` ·
`cat4` groceries `#6F7A3A` · `cat5` activities `#94517A` · `cat6` other `#4D5A6A`.

### Gradients
- **Live:** `context.colors.headerGradient` (ink → ink-2, dark module headers) and
  `context.colors.primaryGradient` (saffron → saffron-dark, CTAs/accent icons).
- **`AppGradients` (terracotta/olive/teal/gray) in `gradient_tokens.dart` is dead**
  — left over from the archived onboarding. Do not use; see [§13](#13-known-drift--debt).

### Module accents
Only **Ledger** is colored (saffron). All other module accents resolve to ink-3 —
modules differentiate by **icon, not color**. (Gear/Logistics/Vault/Memories tokens
persist but the features were stripped in Phase 39 — dead.)

---

## 3. Typography

Three families, one Arabic display face. Helpers live on `AppTypography`; ambient
styles come from `Theme.of(context).textTheme.*` (wired to the same families).

| Family | Helper | Use |
|---|---|---|
| **Instrument Serif** *(italic)* | `AppTypography.display(...)` | Wordmark, screen titles, hero numerals. The emotional voice — sparingly. |
| **Geist** (sans) | `AppTypography.sans(...)` | All UI text, labels, buttons, body. |
| **Geist Mono** (tabular) | `AppTypography.mono(...)` | All money amounts, currency codes, dates, uppercase captions ("ACTIVE JOURNEYS"). |
| **Reem Kufi** | `AppTypography.arabicDisplay(...)` | Arabic-script display moments (no italic — Arabic doesn't mark emphasis that way). |

Fonts are **bundled app assets** (`pubspec.yaml` `flutter: fonts:`), not fetched
at runtime — no `GoogleFonts.getFont` in `lib/` (guard-tested). Tabular figures
use `FontFeature.tabularFigures()` **without** slashed-zero (a slashed 0 reads as
Ø on amounts and invite codes, #148).

### Type scale (`TextTheme`)
| Slot | Family | Size | Weight | Tracking |
|---|---|---|---|---|
| `displayLarge` | Serif italic | 44 | 400 | -1.0 |
| `displayMedium` | Serif italic | 36 | 400 | -0.6 |
| `displaySmall` | Serif italic | 28 | 400 | -0.4 |
| `headlineLarge` | Serif italic | 24 | 400 | -0.3 |
| `headlineMedium` | Geist | 20 | 600 | — |
| `headlineSmall` | Geist | 18 | 600 | — |
| `titleLarge` | Geist | 17 | 600 | — |
| `titleMedium` | Geist | 15 | 600 | — |
| `titleSmall` | Geist | 13 | 600 | — |
| `bodyLarge` | Geist | 16 | 400 | — |
| `bodyMedium` | Geist | 14 | 400 | — |
| `bodySmall` | Geist | 12 | 400 | — |
| `labelLarge` | Geist | 14 | 600 | — |
| `labelMedium` | Geist | 12 | 500 | — |
| `labelSmall` | Geist | 11 | 500 | +0.3 |

Display (serif) slots use `textPrimary`. Body slots default to `textSecondary`.
All non-display slots carry tabular figures so inline numbers stay aligned.

---

## 4. Spacing & radius

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

`radiusMedium` (12) / `radiusLarge` (16) are the **legacy scale** — kept for the
~19 call sites that predate the semantic radii; those migrate onto the semantic
tokens in Phase 2 (§13 D2). Don't reach for `radiusMedium`/`radiusLarge` in new code.

### Button & touch sizing
Prominent buttons: min `64×52`, padding `(24,14,24,16)` directional, pill shape,
Geist 15/600. Text buttons: min `48×44`. Standard control height: **52dp**
(`buttonHeight`). Never ship a tap target under 44dp.

---

## 5. Elevation & shadow

Three levels on `context.shadows`. Cards are **flat by default** (elevation 0 +
hairline border or `raised`), not Material-elevated.

| Token | Use | Light spec |
|---|---|---|
| `flat` | Default. Borders do the separating. | `[]` |
| `raised` | Cards lifted off paper, sticky headers. | gray-900 @ 4% blur10 y4 + @ 2% blur4 y2 |
| `floating` | Modals, FAB, popovers. | gray-900 @ 7% blur24 y8 + @ 3% blur10 y4 |

Shadows are warm-neutral (gray-900 base) at low opacity — soft, never hard
drop-shadows. Dark theme uses a black base at higher opacity.

---

## 6. Motion

Canonical tokens on `context.motion` (`AppMotionTokens`):

| Token | Duration | Curve | Use |
|---|---|---|---|
| `motion.quick` | 120ms | `motion.curveStandard` (`easeInOut`) | Tap feedback (`TapBounce` → scale 0.97). |
| `motion.standard` | 200ms | `motion.curveStandard` (`easeInOut`) | Most state transitions, toggles. |
| `motion.emphasis` | 300ms | `motion.curveEmphasis` (`easeOutCubic`) | Banners (`OfflineBanner`), sheets, entrances. |

The tokens exist; **adoption is the open work** — durations are still scattered
(100–800ms) across ~20 `flutter_animate` call sites, migrated onto `context.motion`
in Phase 2 (§13 D6). Use the tokens in new code.

Entrance animations (`EmptyStateView`, `flutter_animate` `.animate()`) schedule
tickers — **widget tests landing on empty/error states must `pumpAndSettle()`** or
teardown throws a pending-timer error. Prefer wrapping tappable cards/icons in
`TapBounce` over hand-rolling press scales.

---

## 7. Iconography & RTL

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

Full rules: [LOCALIZATION.md § RTL](./LOCALIZATION.md).

---

## 8. Money display

`RAmount` is the canonical money widget — never format currency by hand in a
`Text`.

- Geist Mono, tabular, tiered sizing: currency prefix 0.42× · whole part 1.0× ·
  decimals 0.55×.
- `tone: AmountTone.auto` colors by sign (sage + / rust − / ink 0). Override to
  `ink` for neutral totals where positive ≠ "good".
- Decimals are currency-driven: **OMR/KWD/BHD = 3** (baisa), most others = 2,
  JPY = 0. Handled inside `RAmount`/`MoneySerializer` — don't pre-format.
- App is **OMR-only for 1.0** (#61) — every write path hardcodes `'OMR'` on
  purpose. `RAmount` is per-currency-correct for when multi-currency lands.

---

## 9. Component catalog

Full API in [SHARED-WIDGETS.md](./SHARED-WIDGETS.md). Reach for these before
hand-rolling. The brand-defining ones:

| Widget | Role |
|---|---|
| `RAmount` | Canonical money display (see §8). |
| `RAvatar` / `RAvatarStack` | Person initials stamp, stable per-name color. **One stable color per person, everywhere — never override `hue` for identity** (DEC-3 / #149). |
| `WordmarkLogo` | Italic "Rihla" + saffron flourish. |
| `CoverArt` | Procedural ticket-card scenery (no photo assets). |
| `SectionHeader` | Uppercase mono section label + optional "See all". |
| `ModuleHeader` | Dark-gradient module header (back, title, subtitle, actions). |
| `EmptyStateView` | Icon + title + message + optional CTA for empty/error. |
| `LoadingButton` | 52dp pill button with spinner state. |
| `SkeletonLoader` | Layout-matched shimmer placeholders. |
| `OfflineBanner` | Self-managing amber connectivity strip. |
| `GrainOverlay` | Paper-grain texture (3.5% hero / 2% dark headers). |
| `TapBounce` | Press-scale feedback wrapper (120ms / 0.97). |
| `DirectionalIcon` | RTL-mirroring nav glyph wrapper. |

**Promote to `shared/` when:** used in 2+ features · single nameable
responsibility · reads tokens not literals · testable in isolation. Otherwise keep
it in the feature dir until a second feature copies it.

---

## 10. Screen patterns

The canonical screen skeleton:

```
Scaffold (scaffoldBackground = paper)
 └─ body: Column
     ├─ OfflineBanner()              // self-managing, top of body
     ├─ ModuleHeader(...)            // inner screens; or wordmark top-bar on Home
     └─ content (ListView / CustomScrollView)
         ├─ SectionHeader('UPPERCASE LABEL')
         ├─ cards / rows (flat card + hairline, or raised)
         └─ EmptyStateView(...)      // when the list is empty
```

- **App bar:** transparent, elevation 0, centered. Inner screens show a large
  serif-italic title; Home shows the wordmark (avatar left · wordmark center · bell
  right).
- **Cards:** white `cardSurface`, radius per §4, `flat`+hairline or `raised`. Pad
  with `space16`.
- **List rows:** leading `RAvatar`/icon · title (`titleMedium`) + subtitle
  (`bodySmall`/mono date) · trailing `RAmount` or `DirectionalIcon` chevron.
- **States — every async surface needs all four:** loading (`SkeletonLoader`
  matching the layout) · empty (`EmptyStateView`) · error (`EmptyStateView` variant)
  · content. Don't ship a spinner-only or a bare error string.
- **Top-level direct-entry screens guard back:** `if (!context.canPop()) go('/home')`.
  Nested sub-routes don't need it (GoRouter materializes ancestors). See
  CLAUDE.md § Routing landmines before touching this.

---

## 11. Voice & copy

- Section labels: UPPERCASE, mono, letter-spacing ~1.2 (`SectionHeader`).
- Sentence case for titles, buttons, body. No Title Case On Everything.
- Currency: ISO code + figure ("OMR 10.500"), code-first, all locales.
- Localize every user-facing string via `context.l10n` — no literals in widgets.
  Arabic emits Western digits via `intl 'ar'` (known; see notation memory).

---

## 12. Enforcement

What keeps the system unified, split by teeth:

**CI-gated (build fails):**
- No hardcoded `Color(0x…)` outside `lib/core/theme/tokens/` (color lint).
- 80% line coverage; `flutter analyze` clean; `prefer_const_constructors`.

**Convention (reviewer-enforced — the ~50% adherence gap):**
- Spacing/radius via `context.spacing` + token radii, not literals.
- Text via `AppTypography.*` / `textTheme.*`, not raw `TextStyle(fontSize:…)`.
- Directional APIs + `DirectionalIcon` (greps in `tool/check_release_readiness.sh`).
- Shared widgets before custom; `RAmount` for money; `RAvatar` for people.

**Adding a token:** add the field to the relevant `tokens/*.dart` (+ `copyWith` +
`lerp`), wire it into both `light` and `dark` instances, and — for a one-off
gradient/literal that genuinely can't be a token — annotate
`// design-token-justified: <reason>` so the lint allows it.

**Adding/removing UI:** when you remove an element, grep tests for its label/key
and delete obsolete assertions (don't patch them).

---

## 13. Known drift & debt

Honest current state (2026-06-06) — the gap between "system" and "adherence". These
are the enforcement backlog:

| # | Drift | Evidence | Action |
|---|---|---|---|
| D1 | **Token adoption ~50%.** ~92 `lib` files hardcode spacing/radius/text. | 81/173 files use `context.*`; 360 literal `SizedBox`, 179 literal `BorderRadius.circular`, 94 raw `TextStyle(`. | Phased per-feature refactor → tokens/primitives. |
| D2 | **Radius — semantic tokens landed; call sites pending.** Canonical `radiusInput/Card/Sheet/Pill` now exist & match `AppTheme`; ~19 legacy `radiusMedium`/`radiusLarge` call sites not yet migrated. | §4. | ✅ Phase 1 (tokens). Phase 2: migrate the 19 call sites per screen. |
| D3 | **`AppGradients` is dead.** terracotta/olive/teal/gray — archived onboarding only. | No screen references it (grep); only `token_promotions_test` + `design_tokens_test` gradient cases. | Cleanup PR — delete with its tests (one-PR-one-thing; coverage-neutral). |
| D4 | **Group avatar palette is dead code, not a live mismatch.** `AppGroupAvatarColors` (teal/emerald/amber) + `groupAvatarSlot()` have **zero live callers** — groups already render on-brand via `RAvatar`. | grep: no `context.colors.groupAvatarSlot(` in `lib`. | Cleanup PR — delete with D3 (was wrongly scoped as a palette fix). |
| D5 | **Dark theme untuned.** Compiles, legible, not designed. | `color_tokens.dart` dark docstring; `app_theme.dart` darkTheme is a stub. | Tune dark after light adherence lands. |
| D6 | **Motion tokens landed; adoption pending.** `context.motion` (quick/standard/emphasis + curves) exists; ~20 ad-hoc `flutter_animate` durations not yet migrated. | §6. | ✅ Phase 1 (tokens). Phase 2: migrate ad-hoc durations. |
| D7 | **Dead module tokens.** Gear/Logistics/Vault/Memories color fields persist post-Phase-39. | `color_tokens.dart`. | Cleanup PR (low priority — inert; 50-field surgery on copyWith/lerp/`_allBlack`). |

Track adherence by re-running the §13 greps; the counts are the metric.
