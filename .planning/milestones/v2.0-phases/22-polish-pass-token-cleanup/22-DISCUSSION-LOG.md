# Phase 22: Polish Pass & Token Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 22-polish-pass-token-cleanup
**Areas discussed:** Haptic feedback scope, M3 motion transitions, Texture & grain overlays, Animated balance counters

---

## Haptic Feedback Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Required actions only | Add expense, record settlement, join group — just the 3 success criteria items | :heavy_check_mark: |
| All write actions | Also add haptics to create group, create event, delete expense, etc. | |
| Write actions + destructive | All write actions plus warning haptic on deletes | |

**User's choice:** Required actions only
**Notes:** HapticService already wired in 22 files for baseline interactions

### Haptic Pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Success pattern | HapticService.success() — double medium impact with 100ms gap | :heavy_check_mark: |
| Medium single tap | HapticService.medium() — single medium impact | |
| Light click | HapticService.lightClick() — minimal tactile feedback | |

**User's choice:** Success pattern

### Haptic Timing

| Option | Description | Selected |
|--------|-------------|----------|
| On tap | Fire immediately when user taps action button | :heavy_check_mark: |
| On success | Fire after Firestore write completes | |
| Both | Light click on tap, success on completion | |

**User's choice:** On tap

---

## M3 Motion Transitions

### Motion Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Key transitions only | ContainerTransform for cards, SharedAxis for forms, keep slide for deep nav (~8-10 routes) | :heavy_check_mark: |
| All major routes | Replace slide-right everywhere with M3 patterns (~20+ routes) | |
| Minimal — just cards | Only ContainerTransform on card→detail (~4-5 routes) | |

**User's choice:** Key transitions only

### Card Morph Style

| Option | Description | Selected |
|--------|-------------|----------|
| Full ContainerTransform | Card physically expands to fill screen via OpenContainer | :heavy_check_mark: |
| FadeThrough only | Card fades out, detail fades in | |
| SharedAxis horizontal | Card slides left, detail slides from right | |

**User's choice:** Full ContainerTransform

### Form Step Transition

| Option | Description | Selected |
|--------|-------------|----------|
| SharedAxis vertical | Content slides up on advance, down on back | :heavy_check_mark: |
| SharedAxis horizontal | Content slides left/right | |
| Keep current | Don't change form step transitions | |

**User's choice:** SharedAxis vertical

### Tab Switch Motion

| Option | Description | Selected |
|--------|-------------|----------|
| FadeThrough | M3 standard for top-level destinations | :heavy_check_mark: |
| Keep instant swap | IndexedStack instant swap, keeps tab state | |
| Crossfade only | Simple AnimatedSwitcher crossfade | |

**User's choice:** FadeThrough

---

## Texture & Grain Overlays

### Texture Type

| Option | Description | Selected |
|--------|-------------|----------|
| Paper grain noise | Subtle tileable noise at ~3-5% opacity, handmade paper feel | :heavy_check_mark: |
| Soft radial gradients | Warm color gradients, no actual texture | |
| Grain + gradient combo | Both gradient and noise | |
| Frosted glass / blur | BackdropFilter blur effect | |

**User's choice:** Paper grain noise

### Texture Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Hero cards + scaffold | Grain on hero cards and scaffold background, content cards stay clean | :heavy_check_mark: |
| All cards and surfaces | Everything gets grain | |
| Scaffold background only | Only page background | |
| Hero cards only | Just summary hero cards | |

**User's choice:** Hero cards + scaffold

### Header Grain

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — subtle grain on headers | ~2% opacity on dark gradient ModuleHeaders | :heavy_check_mark: |
| No — headers stay clean | Dark gradient stays smooth | |

**User's choice:** Yes — subtle grain on headers

---

## Animated Balance Counters

### Counter Style

| Option | Description | Selected |
|--------|-------------|----------|
| Smooth number lerp | TweenAnimationBuilder, 600ms easeOutCubic | :heavy_check_mark: |
| Rolling digit counter | Each digit rolls independently like odometer | |
| Fade crossfade | AnimatedSwitcher, old fades out new fades in | |

**User's choice:** Smooth number lerp

### Counter Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Home + Ledger | BalanceHeroCard and LedgerHeroCard (success criteria screens) | :heavy_check_mark: |
| All amount displays | Every number that changes across the app | |
| Home only | Just BalanceHeroCard | |

**User's choice:** Home + Ledger

### Color Animation

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — animate color too | ColorTween green↔red when balance crosses zero | :heavy_check_mark: |
| No — instant color swap | Number animates but color snaps immediately | |

**User's choice:** Yes — animate color too

---

## Claude's Discretion

- Grain texture asset format, tile size, exact opacity values
- AppColors→token bulk migration strategy
- ContainerTransform duration/easing
- Whether to extract animated counter into shared widget

## Deferred Ideas

None
