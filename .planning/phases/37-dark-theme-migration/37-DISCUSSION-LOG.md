# Phase 37: Dark Theme Migration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-17
**Phase:** 37-dark-theme-migration
**Areas discussed:** Migration strategy, Theme toggle UX, textMuted replacement, Verification, Lint/CI, Hardcoded literals, Spacing scope

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Migration strategy & batching | 917 refs across 106 files — one big PR, shared-widgets-first waves, or feature mini-PRs | (delegated) |
| Theme toggle UX & default | Settings placement, default mode, persistence, switch animation | (delegated) |
| textMuted replacement strategy | 134 uses — add WCAG-AA muted token, collapse to textSecondary, or case-by-case triage | (delegated) |
| Verification approach | Golden screenshot tests, manual checklist, runtime WCAG contrast assertions, or combo | (delegated) |

**User's choice:** "take creative control on this" — Claude makes the calls for all gray areas.

**Notes:** User explicitly delegated decision-making after seeing the gray-area menu. All decisions in CONTEXT.md are Claude's recommendations, justified inline.

---

## Migration Strategy & Batching

| Option | Description | Selected |
|--------|-------------|----------|
| One big PR (all 917 refs at once) | Single atomic landing; no intermediate broken state | |
| Shared-widgets-first, then feature waves | Sequential infra → shared → 4 parallel feature waves → cleanup → UX/verify | ✓ |
| Feature mini-PRs (one per feature folder) | Many small PRs; high review overhead; partial dark theme during transition | |

**Recommendation rationale:** Wave-based with parallel features (3a-3d) minimizes review burden while keeping each commit atomic and reverseable. Shared widgets propagate first so feature waves don't fight regressions.

---

## Theme Toggle UX & Default

| Decision | Choice |
|----------|--------|
| Default mode | `ThemeMode.system` |
| Settings placement | New "Display" section in profile_screen.dart, above About |
| Toggle UI | Tile → bottom sheet with 3 radio options |
| Persistence | SharedPreferences key `theme_mode` |
| Animation | None (instant Flutter rebuild) |

**Rationale:** Modern app default is "follow OS." Bottom sheet keeps Settings list dense. Skipping animation avoids full-tree rebuild jank for zero UX gain.

---

## textMuted Replacement Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Add new WCAG-AA muted token | New `textMutedAccessible` (#6B7280-ish) replaces all 134 uses | (deferred — D-12) |
| Collapse all to textSecondary | Single replacement everywhere | |
| Case-by-case triage | Functional → textSecondary; decorative → keep textMuted with justification | ✓ |

**Rationale:** Some uses are genuinely decorative (separator dots, faint glyphs) where 2.86:1 is fine because there's no information being conveyed. Forcing all to textSecondary loses subtlety. CI guard ensures justification comment exists for every remaining `textMuted`.

---

## Verification Approach

| Layer | Decision |
|-------|----------|
| Golden screenshot tests | 10 screens × 2 themes = 20 goldens |
| Runtime contrast assertion | Walks AppColorTokens.dark text/bg pairs, asserts WCAG AA |
| CI grep guard | tool/check_theme_purity.sh wired into release_android.yml |
| Manual QA | MANUAL-QA.md checklist, supplemental |

**Rationale:** Combo approach. Goldens catch visual regressions; contrast test catches new accessibility violations; grep guard prevents migration backsliding.

---

## Lint / CI Enforcement

| Option | Selected |
|--------|----------|
| Custom analyzer plugin (dart_code_metrics) | |
| Pre-commit hook | |
| Simple bash CI grep | ✓ |

**Rationale:** Bash grep is zero-dependency, instantly debuggable, easy to relax/extend. Sufficient guard for this codebase size.

---

## Hardcoded Color(0xFF...) Handling

| Promotion target | Decision |
|------------------|----------|
| Group avatar palette (5 colors) | New `AppGroupAvatarColors` token family with light/dark variants |
| Onboarding gradients | New `AppGradients` token family |
| Module hero gradients | Reuse `AppGradients` |
| Category colors | Stay in `expense_category_model.dart` but source from tokens |
| app_theme.dart literals (4) | Treat as bugs — fix in Wave 1 |
| Inline literals allowed | Only with `// design-token-justified:` comment |

---

## Spacing Token Adoption (DARK-04)

| Approach | Selected |
|----------|----------|
| Sweep all numeric spacing across codebase | |
| Pragmatic: only when touching files for color migration | ✓ |
| New widgets must use tokens | ✓ |

**Rationale:** Spacing-only sweeps are perpetual followup work. Catching it during the file-touching pass is the highest leverage moment.

---

## Claude's Discretion

The entire phase. User said "take creative control."

## Deferred Ideas

- Animated theme transitions
- Per-screen dark-mode redesigns
- Accent color customization
- Spacing-only sweep of untouched files
- WCAG AAA high-contrast theme
- Dark theme for golden test CI image
