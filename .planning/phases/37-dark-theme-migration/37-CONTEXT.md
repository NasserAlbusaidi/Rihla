# Phase 37: Dark Theme Migration - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Source:** Discuss-phase (user delegated all gray areas — "take creative control")

<domain>
## Phase Boundary

Complete the dark-theme rollout that began with the slate-based `AppColorTokens.dark` palette landing on Apr 16. Specifically:

1. **Migrate every widget in `lib/`** from direct `AppColorTokens.light.*` reads to `context.colors` (the `AppThemeExtensions on BuildContext` extension at `lib/core/theme/tokens/domain_aliases.dart:19`). Scope: ~917 references across 106 files.
2. **Wire `darkTheme` into `MaterialApp`** and add a Settings theme toggle (System / Light / Dark) persisted via SharedPreferences.
3. **Retire `textMuted` (#9CA3AF, 2.86:1)** from functional text roles. Triage all 134 uses across 59 files.
4. **Adopt `AppSpacingTokens.standard`** opportunistically when files are touched for color migration.
5. **Promote hardcoded `Color(0xFF...)` literals** (105 outside `tokens/`) to named tokens or tag with inline justification.
6. **Add CI guard + golden screenshot tests** to prevent regression.

Out of scope (deferred):
- Per-screen redesign (visual polish stays as-is — palette swap only)
- Animated theme switch transitions (Flutter's built-in instant rebuild is acceptable)
- New token families beyond what migration requires
- Migrating `lib/test/` mocks or generated `firebase_options.dart`

</domain>

<decisions>
## Implementation Decisions

### Migration Strategy & Batching

- **D-01:** Wave-based migration, shared-widgets-first. Five waves total:
  - **Wave 1 — Theme infrastructure (1 plan, blocking, sequential):** Wire `AppTheme.darkTheme` into `MaterialApp`; add `themeModeProvider` (StateNotifierProvider) + ThemeMode persistence; replace `Color(0xFF...)` literals inside `lib/core/theme/app_theme.dart` with token refs (`onSecondary`, `onError`, `bodyMedium.color`, `bodyLarge.color` at lines 23, 25, 115, 121); ensure `_buildTextTheme` resolves via `ColorScheme`. Adds context.colors-based extension already exists — verify no gaps.
  - **Wave 2 — Shared widgets (1 plan, sequential after W1):** Migrate `lib/shared/widgets/` (16 files) + `lib/core/theme/error_widgets.dart` + `lib/core/router/app_router.dart` (transition shells). These propagate to every feature.
  - **Wave 3 — Feature waves (4 parallel plans):**
    - 3a: `auth/`, `onboarding/`, `settings/`, `home/`
    - 3b: `groups/` (largest surface — 21 files)
    - 3c: `events/`, `ledger/` (most LOC after groups)
    - 3d: `gear/`, `logistics/`, `vault/`, `memories/`, `activity/`
  - **Wave 4 — Token cleanup (1 plan, sequential after W3):** Promote group avatar palette → `AppGroupAvatarColors`; gradient pairs → `AppGradients`; category colors stay in `expense_category_model.dart` but become token refs; textMuted triage; spacing token sweep on touched files only.
  - **Wave 5 — Settings UX + verification (1 plan, sequential after W4):** Settings "Display" section with theme tile → bottom sheet (System/Light/Dark radio); golden screenshot tests; runtime contrast assertion test; CI guard script.

- **D-02:** Each wave is its own atomic commit. Plans must explicitly list `files_modified` so parallel waves in W3 don't collide. Plans in W3 are independent — no shared mutable state between feature folders.

- **D-03:** Migration is mechanical — `s/AppColorTokens\.light\.(\w+)/context.colors.$1/g` style. No widget redesign. If a color was intentionally light-only (e.g., a hardcoded warm-sand splash background), it gets a token-justified inline literal in Wave 4, not a theme-aware swap.

### Theme Toggle UX & Default

- **D-04:** Default mode = `ThemeMode.system`. Respects OS setting; user can override.
- **D-05:** Placement = new "Display" section in `lib/features/settings/screens/profile_screen.dart`, positioned above the existing About section. Single tile labeled "Theme" showing current mode (e.g., "System • Following device").
- **D-06:** Tap opens a bottom sheet (`showModalBottomSheet`) with three radio options: System / Light / Dark, each with a one-line description ("Follow device setting" / "Always light" / "Always dark"). Selection persists immediately and dismisses sheet.
- **D-07:** ~~Persistence = SharedPreferences key `theme_mode` storing string `'system' | 'light' | 'dark'`. Reuse existing `sharedPreferencesProvider` in `lib/main.dart`. Hydration in `themeModeProvider` constructor (synchronous read like `onboardingCompleteProvider`).~~ **Superseded by D-07a (2026-04-18):** Persistence already exists on `settingsProvider` — `AppSettings.theme: AppThemeMode` is already stored via SharedPreferences and exposed via `SettingsNotifier.setThemeMode(AppThemeMode)`. Reuse this — no new persistence layer.
- **D-08:** ~~State = `themeModeProvider` is a `StateNotifierProvider<ThemeModeNotifier, ThemeMode>`. Place in `lib/features/settings/providers/theme_mode_provider.dart`.~~ **Superseded by D-08a (2026-04-18):** No new provider. Read theme via `ref.watch(settingsProvider.select((s) => s.theme.toMaterialThemeMode()))`. Writes call `ref.read(settingsProvider.notifier).setThemeMode(AppThemeMode)`. Rationale: creating a parallel `themeModeProvider` produces dual source of truth against the existing `AppSettings.theme` field. Add `AppThemeMode.toMaterialThemeMode()` extension if it does not yet exist.
- **D-09:** Animation = none (instant). Flutter's `MaterialApp.themeMode` swap is acceptable. No `AnimatedTheme` wrapper — adds rebuild cost during full-tree theme change with no UX win.
- **D-10:** ~~Wiring = `MaterialApp.router(theme: AppTheme.lightTheme, darkTheme: AppTheme.darkTheme, themeMode: ref.watch(themeModeProvider))` in the root.~~ **Superseded by D-10a (2026-04-18):** Wiring = `MaterialApp.router(theme: AppTheme.lightTheme, darkTheme: AppTheme.darkTheme, themeMode: ref.watch(settingsProvider.select((s) => s.theme.toMaterialThemeMode())))` in the root.

### textMuted Replacement Strategy

- **D-11:** Triage rule (applied per-call-site, not blanket replacement):
  - **Functional text** (labels, amounts, body copy, hints, accessibility labels) → migrate to `context.colors.textSecondary` (#6B7280, WCAG AA 4.69:1 on white per existing token).
  - **Pure decorative** (separator dots `•`, faint chevrons in inactive states, divider-like inline glyphs) → keep `context.colors.textMuted` BUT must be preceded by inline comment `// textMuted-decorative-justified: <reason>` (one-line, the reason names the visual element).
- **D-12:** No new token added in this phase. If verification surfaces a gap (e.g., textSecondary too dark on dark theme for a specific role), add `textMutedAccessible` in Wave 4 — defer the call until evidence appears.
- **D-13:** Wave 3 plans must include a `textMuted Triage Pass` task per feature subdirectory. Output: every remaining `textMuted` reference has the justification comment, or is converted to `textSecondary`.
- **D-14:** CI guard (Wave 5) fails build if `context.colors.textMuted` (or `AppColorTokens.light.textMuted`) appears in `lib/` without the preceding `// textMuted-decorative-justified:` comment.

### Hardcoded Color(0xFF...) Handling

- **D-15:** Promote to named tokens — DO NOT leave inline:
  - Group avatar slot palette (`group_card.dart` lines 38-42, 5 colors) → `lib/core/theme/tokens/group_avatar_colors.dart` exposing `AppGroupAvatarColors.lightSlots[]` and `.darkSlots[]`. Accessor: `context.colors.groupAvatarSlot(index)`.
  - Onboarding gradient pairs (`onboarding_screen.dart` lines 43, 50) → `AppGradients.terracotta`, `.olive`, `.teal` etc. — light + dark variants. New file `lib/core/theme/tokens/gradient_tokens.dart`.
  - Module hero gradients (`ledger_screen.dart:377`, `activity_feed_screen.dart:150`, etc.) → reuse `AppGradients` family. One named gradient per module.
  - Category colors in `expense_category_model.dart` (line 73 + similar) → keep colors local to the model file BUT each color becomes a const ref to `AppColorTokens` semantic colors (success, warning, primary, textSecondary). The model returns `Color` but sources from tokens. Document mapping in a header comment.
- **D-16:** Allow inline `Color(0xFF...)` ONLY when:
  - Third-party widget API forces a literal AND the color is not theme-aware (e.g., a fixed brand color in a payment SDK), OR
  - The literal is inside `lib/core/theme/tokens/` (the source of truth files themselves).
  Both cases require comment `// design-token-justified: <reason>` directly above the literal.
- **D-17:** Treat the four `Color(0xFF...)` literals inside `app_theme.dart` (lines 23, 25, 115, 121) as bugs — fix in Wave 1 by sourcing from `ColorScheme` / `AppColorTokens`.

### Verification Approach

- **D-18:** Three-layer verification, all in Wave 5:
  1. **Golden screenshot tests** (Flutter `matchesGoldenFile`) covering 10 key screens × 2 themes = 20 goldens. Screens: home, group_detail, group_settle_up, ledger, add_expense, gear, logistics, settings/profile, memories, onboarding. Generated under `test/goldens/`. Run via `flutter test --update-goldens` once accepted.
  2. **Runtime contrast assertion test** (`test/unit/dark_theme_contrast_test.dart`) — walks every documented `(text, background)` pair in `AppColorTokens.dark` and asserts WCAG AA (4.5:1 normal, 3:1 large/UI). Uses a small contrast helper (port the existing approach from `post-generation-checklist.md` Check 4).
  3. **CI guard script** (`tool/check_theme_purity.sh`) — greps `lib/` for: (a) `AppColorTokens\.light\.` outside `tokens/`, (b) bare `Color(0xFF` outside `tokens/` and without justification comment on prior line, (c) `textMuted` use without `textMuted-decorative-justified` justification. Wired into `.github/workflows/release_android.yml` test step (BEFORE the build step, fail-fast).

- **D-19:** Manual QA checklist (`.planning/phases/37-dark-theme-migration/MANUAL-QA.md`) authored in Wave 5: per-screen light/dark walkthrough run by Nasser before merge. Not blocking — supplemental to the three automated layers.

### Spacing Token Adoption (DARK-04)

- **D-20:** Pragmatic, opportunistic rule: when touching a widget for color migration in any wave, IF a numeric `EdgeInsets`/`SizedBox`/`Padding` value matches a token in `AppSpacingTokens.standard` (4/8/12/16/20/24/32), replace it. One-off odd values (e.g., 6, 14, 18) stay numeric — they are intentional design choices.
- **D-21:** Do not sweep untouched files. Spacing-only PRs across the codebase are deferred to a future phase.
- **D-22:** New widgets (e.g., theme toggle bottom sheet in W5) MUST use `AppSpacingTokens` exclusively for any standard value.

### Lint / CI Enforcement

- **D-23:** No custom analyzer plugin. Use the bash `tool/check_theme_purity.sh` (D-18.3) as the single enforcement point. Three reasons: (a) zero new dependencies, (b) instantly readable failure output, (c) trivial to relax/extend per regex.
- **D-24:** Pre-commit hook NOT added — relies on CI to enforce. Avoids friction during interactive iteration.

### Claude's Discretion

- File naming inside `lib/core/theme/tokens/` (group_avatar_colors.dart, gradient_tokens.dart) — planner can rename if better convention emerges.
- Exact bottom-sheet widget shape (e.g., uses existing `AppBottomSheet` if one exists, or builds inline).
- Golden test breakpoint sizes (default to existing test viewport).
- Order of files within a Wave 3 feature plan (executor decides).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Source of Truth
- `.planning/milestones/v2.4-ROADMAP.md` §"Phase 37: Dark Theme Migration" — goal, success criteria, requirements
- `.planning/milestones/v2.4-REQUIREMENTS.md` §"Dark Theme Migration (Phase 37)" — DARK-01 through DARK-05 acceptance criteria

### Existing Theme Infrastructure (read before planning)
- `lib/core/theme/tokens/color_tokens.dart` — `AppColorTokens.light` (line 188) and `AppColorTokens.dark` (line 241). Source of truth for every color in the app.
- `lib/core/theme/tokens/domain_aliases.dart` — `extension AppThemeExtensions on BuildContext` exposing `context.colors`. Already wired; no new extension needed.
- `lib/core/theme/tokens/spacing_tokens.dart` — `AppSpacingTokens.standard` values (DARK-04 references).
- `lib/core/theme/tokens/shadow_tokens.dart` — light/dark shadow variants (verify dark side is wired in W1).
- `lib/core/theme/app_theme.dart` — `AppTheme.lightTheme` (currently the only theme). `AppTheme.darkTheme` does NOT exist yet — Wave 1 adds it. Note Color(0xFF...) literals at lines 23, 25, 115, 121 (D-17 bugs).

### Project Conventions (read before any UI work)
- `CLAUDE.md` §"Stitch-to-Flutter Workflow" — token mapping rule, textMuted decorative-only rule, module accent rule (Ledger = primary teal, others = gray-500), WCAG AA verified text/background pairs
- `.planning/phases/16-stitch-workflow-design-reference/post-generation-checklist.md` Check 4 — WCAG-verified text/background pairs (used as basis for D-18.2 contrast test)

### Reference Implementations (existing patterns to mirror)
- `lib/features/onboarding/providers/` (or wherever `onboardingCompleteProvider` lives) — pattern for hydrating SharedPreferences-backed state synchronously. Mirror for `themeModeProvider`.
- `lib/main.dart` — `sharedPreferencesProvider` override pattern. The new `themeModeProvider` consumes this provider.
- `lib/core/router/app_router.dart` — `MaterialApp.router` configuration site. Wave 1 modifies this.

### Build / CI Integration Points
- `.github/workflows/release_android.yml` — Wave 5 wires `tool/check_theme_purity.sh` into the test step here.

### What this phase intentionally does NOT touch
- `lib/firebase_options.dart` (auto-generated)
- `test/` mocks (no production color refs)
- Any backend code (Cloud Functions, Firestore rules)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`context.colors` extension** (`lib/core/theme/tokens/domain_aliases.dart:19`) — already implemented. Phase 37 just needs widgets to USE it instead of `AppColorTokens.light.*`.
- **`AppColorTokens.dark`** (color_tokens.dart:241) — slate-based dark palette already defined. Wave 1 wires it; Waves 2-3 don't need to invent dark colors.
- **`AppSpacingTokens.standard`** — already exposes 4/8/12/16/20/24/32. Migration is mechanical replacement.
- **`sharedPreferencesProvider`** in `lib/main.dart` — existing override pattern for the new `themeModeProvider`.
- **Existing bottom sheet patterns** in features (e.g., `edit_name_bottom_sheet.dart`, `record_payment_sheet.dart`) — Wave 5 mirrors structure for the theme picker.

### Established Patterns

- **Riverpod 2.x StateNotifierProvider with sync hydration** — used in `onboardingCompleteProvider`. Mirror for `themeModeProvider`.
- **GoRouter `MaterialApp.router` shell** — Wave 1 swaps `theme:` for `theme: + darkTheme: + themeMode:` here.
- **Soft justification comments** — codebase already uses `// AppColorTokens.light.warning` style comments next to literals (see `event_type_config.dart:71`). Reframe these as `// design-token-justified:` per D-16 OR replace with token refs in Wave 4.

### Integration Points

- **Wave 1 entry**: `lib/core/router/app_router.dart` (MaterialApp config) + `lib/main.dart` (provider override site) + new `lib/features/settings/providers/theme_mode_provider.dart`.
- **Wave 5 settings entry**: `lib/features/settings/screens/profile_screen.dart` (add Display section) + new `lib/features/settings/widgets/theme_picker_sheet.dart`.
- **CI integration**: `.github/workflows/release_android.yml` test step + new `tool/check_theme_purity.sh`.

### Migration Surface (scout numbers, for plan estimation)

- **917** references to `AppColorTokens.light/dark/context.colors` across **106** files
- **134** references to `textMuted` across **59** files
- **105** hardcoded `Color(0xFF...)` literals outside `tokens/`
- Largest features by file count: `groups/` (21 files), `ledger/` (~17), `events/` (~12), `home/` (~6), `settings/` (~7)

</code_context>

<specifics>
## Specific Ideas

- The dark palette is **slate-based** (per memory observation 2677, Apr 16) — not a tinted-light variant. Verification must confirm it reads as a distinct theme, not a "darker beige."
- Module accent rule (CLAUDE.md): Ledger = `primary` teal; all other modules = gray-500. Wave 4 token promotion must preserve this — gradient tokens for non-Ledger modules use gray-based pairs.
- The four `Color(0xFF...)` literals in `app_theme.dart` (D-17) are pre-existing bugs from before the token system landed — fixing them in Wave 1 is a prerequisite, not a stretch goal.
- Group avatar palette uses 5 deterministic slots assigned by group ID hash — D-15's `groupAvatarSlot(index)` accessor preserves the deterministic assignment; only the underlying colors swap per theme.

</specifics>

<deferred>
## Deferred Ideas

- **Animated theme transitions** (e.g., `AnimatedTheme` cross-fade) — Flutter's instant theme rebuild is acceptable per D-09. Revisit if user feedback flags jank.
- **Per-screen redesigns for dark mode** — explicitly out of scope. Palette swap only; visual layouts unchanged.
- **Accent color customization** (let user pick a teal/terracotta/olive primary) — separate phase if requested.
- **Spacing-only sweep across untouched files** — D-21 defers this. Could be a Phase 39+ "tech-debt: spacing tokens" cleanup.
- **High-contrast accessibility theme** (WCAG AAA) — separate phase. This phase targets AA only.
- **Dark theme for golden test runner CI image** — assume default test runner handles `MediaQueryData(platformBrightness: Brightness.dark)` injection in test setup; if not, add infra in a follow-up.
- **Ledger hero gradient palette** — current implementation uses terracotta (`Color(0xFFCC6B49), Color(0xFFE0896A)`) which contradicts CLAUDE.md module accent rule (Ledger = primary teal). Preserved in Phase 37 per D-03 (mechanical migration only, no redesign). Revisit in a follow-up phase with user review — the visual change is non-trivial and affects ledger-screen branding.

</deferred>

---

*Phase: 37-dark-theme-migration*
*Context gathered: 2026-04-17 via /gsd-discuss-phase (user delegated all gray areas)*
