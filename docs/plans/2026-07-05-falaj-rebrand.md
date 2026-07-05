# Falaj Rebrand Program — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> PR-5 (routing/IA) is **Gate-category**: run `/run-the-gate` on its spec BEFORE writing code.

**Goal:** Replace the "Saffron travel-journal" identity (reads as Anthropic/Claude-derivative) with the approved **Falaj (فَلَج)** system — Gulf Modern travel ledger — and land the five friction/IA fixes, without touching money math, l10n keys, or deep-link URLs.

**Architecture:** Pure token-value swap first (field names never change), then font swap through `AppTypography`'s existing per-script machinery (#841), then component redraws as individually-revertable PRs, then the dark pass, then the routing/IA PR (Gate-gated). Approved proposal + research: artifact `https://claude.ai/code/artifact/852544d4-a009-4253-833a-8424e2ab68db`; mockup committed at `docs/design/mockups/falaj-rebrand-proposal.html`.

**Tech Stack:** Flutter theme tokens (`lib/core/theme/tokens/`), bundled Google Fonts (OFL): Bricolage Grotesque · Zain · Spline Sans Mono, golden tests (macOS), `tool/check_theme_purity.sh`.

**Status decision log:**
- 2026-07-05 — Direction approved by owner: **Falaj as proposed** (3/3 judge panel). Runners-up (Kamal — Field Atlas, Jawaz — Midnight Passport) rejected; their grafts are folded in below.
- Open bet: **Zain as Latin UI face** (no 500/600 weights → two-step 400/700 ladder across ~215 `w500/w600` call sites). PR-0 spike decides; pre-agreed fallback = IBM Plex Sans for Latin UI, Zain keeps Arabic + display. Do NOT start PR-2 before the spike verdict is recorded here.

---

## Identity spec (source of truth for all PRs)

### Palette — light "Muscat plaster" / dark "Night navigation"

Verified contrast ratios in parentheses. Field names are the EXISTING `AppColorTokens` fields (historical names, values remapped — same pattern the saffron era used).

| Role (existing field) | Light | Dark | Notes |
|---|---|---|---|
| `primary`, `focusRing`, `focusBorderWarm` | `#8A5D0D` | `#D9A845` | Burnished/lantern brass. White-on-light-primary 5.75:1; dark CTAs use INK text `#1B1F1E` on brass (7.6:1) |
| `primaryDark` | `#6F4A08` | `#B8862B` | CTA gradient end (white 7.9:1) |
| `saffronSoft` (accent-soft) | `#E3E4C9` | `#3A3626` | COOLED from authored `#E9DFC2` — kills the last cream echo |
| `saffronTint`, `selectionFill` | `#F1F2DF` | `#2C2A20` | Tint is NEVER the sole selection signal — always + hairline + tick |
| `scaffoldBackground` | `#F6F7F5` | `#111514` | Plaster / kohl. **Rule: page ground stays G≥R** (Anthropic ivory is R≫B warm) |
| `paperDeep` | `#ECEEE8` | `#0C0F0E` | |
| `cardSurface` | `#FFFFFF` | `#1A201E` | Two-level page-vs-card hierarchy kept |
| `cardSoft`, `inputFill`, `disabled` | `#F1F2ED` | `#242B28` | |
| `textPrimary` | `#1B1F1E` | `#ECEFEA` | Hajar shale / moonlit plaster (15.5:1 / 14.3:1) |
| `ink2` | `#333A38` | `#C9CFC9` | |
| `textSecondary` | `#5C6462` | `#9AA39E` | 5.7:1 / 6.4:1 — AA body |
| `textMuted`, `disabledText` | `#8B918D` | `#6E7773` | Decorative-only contract unchanged |
| `textOnPrimary` | `#FFFFFF` | `#1B1F1E` | Dark flips to ink-on-brass |
| `border`, `borderWarm`, `rule` | `#E3E6E0` | `#2A322F` | Stone-green hairline — kills the sepia rule |
| `rule2` | `#CDD2CA` | `#3A433F` | |
| `success` / `successText` | `#1F7A5C` / `#175A44` | `#4FBE8F` / `#7FD6AE` | Palm emerald (text 7.6:1 / 9.6:1). Green=owed prior kept |
| `error` / `errorText` | `#B03A48` / `#8A2430` | `#E0707B` / `#F0A3AB` | Pomegranate (text 8.2:1 / 8.3:1) |
| `warning`, `offlineBannerBackground` | `#C2410C` | `#E8703A` | **RE-HUED off amber** — old `#F59E0B` collides with brass. Offline banners become icon-led; brass + warning forbidden in one component |
| `cat1` food | `#9C4F2E` | night-tuned in PR-1 | Clay tandoor |
| `cat2` lodging | `#41708F` | 〃 | Harbor blue |
| `cat3` transit | `#575E93` | 〃 | Night-road indigo (old ochre collided with brass) |
| `cat4` groceries | `#6C7A33` | 〃 | Palm-grove olive (distinct from money emerald) |
| `cat5` activities | `#984B7C` | 〃 | |
| `cat6` other | `#4D5A6A` | 〃 | Unchanged |
| `headerGradient` | ink→ink2 (new values) | kohl register | Shale header = "inside an event" |
| `primaryGradient` | `#8A5D0D`→`#6F4A08` | `#D9A845`→`#B8862B` | |

Any `AppColorTokens` field NOT in this table (there will be some — enumerate from the type, not from this doc): derive from the nearest role above, keep the G≥R rule on grounds, and record the derivation in the PR body.

### Type

| Tier | Face | Weights | Notes |
|---|---|---|---|
| Display | Bricolage Grotesque | 600/700/800 **static cuts** | Variable font — bundle static instances, don't wire FontVariation. No italic anywhere in the system (survives Arabic) |
| UI/body BOTH scripts | Zain | 400/700(/800 display) | Gulf-drawn dual-script (Boutros). **PR-0 spike gates this for Latin** |
| Money/codes/eyebrows | Spline Sans Mono | 400/500/700 | Tabular figures, slashedZero OFF (#148). Digits stay Latin-mono in all locales |
| Arabic wordmark | ReemKufi subset (existing) | — | Until a custom square-Kufi lockup is commissioned; never ship Arabic-degraded |

Per-script rules unchanged (#841): Arabic captions = Zain 700, letterSpacing 0, ≥11px; no synthetic italic; no tracking on joined script.

### Signature system + guardrails

- **Falaj fork** (brand device): wordmark underscore, settle-up transfer connector, share-notch tick, sync indicator. **Usage law: full fork ≤1 per screen; the share-notch tick is the only ambient form.** Fork branches trail reading direction (mirrors in RTL).
- **Motion:** existing tokens keep values; add named tokens `stamp` (300ms scale 1.08→1.0, −3°→0°, one-frame ink bloom — grafted from Jawaz) and `flow`. **Continuous flow-motion means "syncing" and nothing else, app-wide** (grafted from Kamal). Reduced-motion falls back to opacity.
- **Polarity carets:** hero money readouts carry ▲/▼ beside the color — owed/owe never color-alone (grafted from Kamal).
- **Tickets:** silhouette + perforation KEPT (KEEP-6); materials re-dress plaster/shale/brass seal; CoverArt repaints to 5 Omani landscape palettes (Hajar dawn, Wadi pool, Khareef, Sharqiya night, Muscat harbor).
- **Stamps:** 12 glyph ids UNCHANGED (Dart SSOT + firestore.rules cross-list — do not touch); redraw as brass port-seals is an optional fast-follow (monogram fallback covers interim).
- **Avatars:** DEC-3 contract untouched (same hash, 8 slots); retint the 8 pairs as a set.
- **Document-close ritual:** share cards/receipts end with fork underscore + "recorded in Rihla" (grafted from Jawaz).
- **KEEP decisions** (explicit, per DESIGN.md §14): BREAK KEEP-1 faces / KEEP-2 hues / KEEP-8 values; KEEP KEEP-3/4/5/6/7 + DEC-3 (structural). Rationales in the proposal artifact §06.

---

## PR sequence

Every PR: `flutter analyze` clean · relevant tests green · `bash tool/check_theme_purity.sh` · conventional commit · PR body `Refs #<tracking-issue>` (program is multi-PR — never `Closes` until the last box) · `/automerge`.

### PR-0 — Type spike (throwaway, no merge required)

**Files:** scratch branch only; screenshot artifacts into the tracking issue.

- [ ] **Step 1:** Bundle Zain 400/700 + Bricolage 700/800 + Spline Sans Mono 400/500 in `pubspec.yaml` fonts on a spike branch.
- [ ] **Step 2:** Hack `AppTypography` families on that branch (no recipe rewrite — family swap only).
- [ ] **Step 3:** Screenshot 3 surfaces in BOTH scripts, light theme: dense ledger (20+ rows), balance hero, settings list.
- [ ] **Step 4:** Verdict against the pre-agreed criteria: 13sp rows legible? 400/700 two-step ladder carries payer-name/note emphasis? Arabic/Latin x-height harmony acceptable?
- [ ] **Step 5:** Record verdict in this file's decision log + tracking issue: **Zain-Latin GO** or **fallback: IBM Plex Sans Latin UI** (Zain keeps Arabic + display). Delete the spike branch (no Schrödinger's branch — it dies same-day).

### PR-1 — Token swap (the signature kill; ships standalone)

**Files:**
- Modify: `lib/core/theme/tokens/color_tokens.dart` (light + dark instances — ALL fields)
- Modify: `lib/core/theme/tokens/shadow_tokens.dart` (warm-neutral base stays; verify vs new grounds)
- Modify: CoverArt palette source (grep `CoverArt` under `lib/shared/widgets/` for the 5 band palettes)
- Modify: `RAvatar` 8-slot palette (`lib/shared/widgets/` — retint as a set)
- Create: `test/unit/theme_contrast_test.dart`
- Regenerate: `test/goldens/` (macOS only)

- [ ] **Step 1 (RED):** Write `test/unit/theme_contrast_test.dart` — table-driven WCAG checks over token PAIRS, both themes: `textPrimary`/`textSecondary` on `scaffoldBackground` + `cardSurface` ≥4.5; `textOnPrimary` on `primary` ≥4.5; `successText`/`errorText` on both surfaces ≥4.5; `warning` vs `primary` must differ in hue (assert ΔH > 20° or hardcode the pair inequality). Run: `flutter test test/unit/theme_contrast_test.dart` → FAILS against saffron values (warning/hue check) or passes vacuously — if vacuous, assert the NEW literal values so the test fails until the swap lands.
- [ ] **Step 2:** Open `color_tokens.dart`, enumerate EVERY field from the class (not from this doc — verification principle 4). Map per the table; derive unlisted fields; note derivations.
- [ ] **Step 3 (GREEN):** Swap light instance values. Run contrast test → passes for light.
- [ ] **Step 4:** Swap dark instance values (incl. night-tuned cat1–6 — write the computed ratio next to each pair in a comment-free PR-body table, not code comments).
- [ ] **Step 5:** CoverArt 5 palettes + RAvatar 8 pairs.
- [ ] **Step 6:** `flutter analyze` && `flutter test` && `bash tool/check_theme_purity.sh`. Regenerate goldens on macOS; review diffs by eye — this is the visual review.
- [ ] **Step 7:** Commit `feat(theme): Falaj token swap — Muscat plaster / night navigation palette (Refs #<issue>)`.
- [ ] **Step 8 (acceptance):** Stranger test on before/after screenshots of home + ledger vs Anthropic screenshots: "which of these is made by the Claude people?" Record outcome in the tracking issue BEFORE starting PR-2/3.

### PR-2 — Font swap

Gated on PR-0 verdict. Bundle static cuts in `pubspec.yaml`; rewrite `AppTypography` recipes (display drops italic → `displayOf` simplifies; Latin weight ladder 400/700 remap across the ~215 `w500/w600` call sites — mechanical sweep, or Plex keeps 500/600 if fallback won); keep `FontFeature.tabularFigures()` w/o slashed zero; test-label sweeps for changed goldens. Detailed task breakdown at kickoff.

### PR-3 — Components (each revertable)

Wordmark fork underscore (swash retired; ReemKufi Arabic stays) · transfer-connector fork painter (**dashed arrow stays until the painter passes 16px/24px/RTL goldens**) · `GrainOverlay` → delete light grain, add ≤3%-opacity star-grid for dark heroes (tokenized) · ticket re-dress + brass corner seal · share-tick in `SectionHeader` · `stamp`/`flow` motion tokens + seal-settle animation · polarity carets in the hero `RAmount` surfaces. Detailed breakdown at kickoff.

### PR-4 — Dark pass (absorbs D5)

Tune night-navigation dark end-to-end, then revisit the light-only default (D5a: `AppSettings.themeMode` back to system). Update DESIGN.md §13 D5/D5a. Detailed breakdown at kickoff.

### PR-5 — IA / friction fixes (**Gate-category — `/run-the-gate` the spec first**)

One-tap FAB → top-priority target (reuse `_priority` sort in `active_journeys_provider.dart`; "Adding to <event> · change" inside the editor Where card; sheet = escape hatch) · smart-forward group rows (1 open event → `/group/:gid/event/:eid`; overview via header; URLs unchanged) · hero → per-group breakdown sheet deep-linking `settle-up?memberId=` · standalone module routes become shims into `EventCommandCenter` tabs (**tab from PATH segment, never `state.extra`**; add/edit editor routes stay real screens) · global `/search`. Routing constraints inventory: proposal artifact §02 + CLAUDE.md routing landmines. May land before or after PR-1–4.

### DESIGN.md v2

Rewrite DESIGN.md against shipped reality after PR-3 (not before — the doc follows the code). Carry over: token architecture, enforcement, KEEP list updated with the decisions above, fork usage law, G≥R ground rule, flow-means-syncing rule.

---

## Out of scope (explicit)

- App name/wordmark text: **Rihla stays Rihla** — Falaj names the design system only.
- Money math, `MoneySerializer`, `firestore.rules`, l10n keys, Iconsax icon set, spacing/radius/motion token VALUES, glyph-id lists.
- Custom square-Kufi wordmark commission (external; ReemKufi subset is the indefinite fallback).
- Port-seal SVG redraw of the 12 stamps (optional fast-follow after PR-3).
