---
phase: 25-profile-screen-core
plan: "01"
subsystem: profile
tags: [profile, identity, stats, settings, tdd]
dependency_graph:
  requires:
    - lib/core/providers/settings_provider.dart
    - lib/features/groups/providers/group_provider.dart
    - lib/features/groups/providers/group_balance_provider.dart
    - lib/features/events/providers/event_provider.dart
    - lib/core/theme/tokens/color_tokens.dart
    - lib/core/utils/formatters.dart
  provides:
    - lib/features/settings/screens/profile_screen.dart
    - lib/features/settings/widgets/edit_name_bottom_sheet.dart
    - lib/features/settings/widgets/profile_stats_section.dart
    - lib/shared/widgets/initials_circle.dart
    - lib/features/settings/providers/profile_stats_provider.dart
    - lib/features/settings/keys/profile_keys.dart
  affects:
    - lib/core/providers/settings_provider.dart (extended with propagateDisplayName)
tech_stack:
  added: []
  patterns:
    - Provider (not StreamProvider) for multi-source aggregation with ref.watch in loops
    - TDD red-green-refactor across unit and widget tests
    - flutter_animate delay-based entrance animations with pump(500ms) in tests
    - unawaited fire-and-forget Firestore batch with silent catch
key_files:
  created:
    - lib/features/settings/keys/profile_keys.dart
    - lib/shared/widgets/initials_circle.dart
    - lib/features/settings/providers/profile_stats_provider.dart
    - lib/features/settings/widgets/edit_name_bottom_sheet.dart
    - lib/features/settings/widgets/profile_stats_section.dart
    - lib/features/settings/screens/profile_screen.dart
    - test/unit/profile_stats_provider_test.dart
    - test/features/profile/profile_screen_test.dart
  modified:
    - lib/core/providers/settings_provider.dart (propagateDisplayName + unawaited)
    - test/unit/settings_notifier_test.dart (IDENT-03 test added)
decisions:
  - "Removed FakeSettingsNotifier complexity from test harness — used sharedPreferencesProvider override + profileStatsProvider override directly (simpler, more idiomatic)"
  - "Tests pump(500ms) to advance past flutter_animate animation timers — avoids pending-timer test failures"
  - "profileStatsProvider uses Provider (not StreamProvider) to allow ref.watch in for-loop — same pattern as groupBalancesProvider"
  - "propagateDisplayName silently catches all errors — no UI feedback for Firestore fail per D-15"
metrics:
  duration: "6m 46s"
  completed_date: "2026-04-01"
  tasks: 2
  files_created: 8
  files_modified: 2
  tests_added: 15
  tests_total: 804
---

# Phase 25 Plan 01: Profile Screen Core — Summary

## One-liner

Profile identity + cross-group stats with earthy design: InitialsCircle, profileStatsProvider, EditNameBottomSheet, ProfileStatsSection, ProfileScreen, and Firestore display-name propagation via fire-and-forget batch write.

## What Was Built

### Task 1: Data layer + settings extension (TDD)

**ProfileKeys** — 11 semantic test keys for all profile screen elements, replacing the need to find by text (rename-resilient).

**InitialsCircle** — Reusable 64dp/32dp circular avatar with terracotta fill (`focusBorderWarm`). Extracts initials: single-word → first char, multi-word → first + last initial. Font size scales at `size * 0.38`.

**profileStatsProvider** — `Provider<AsyncValue<ProfileStats>>` that aggregates group count (from `userGroupsProvider`), event count (from `groupEventsProvider.family` per group), and total spending (from `groupBalancesProvider.family` per group). Uses the same `Provider` (not `StreamProvider`) pattern as `groupBalancesProvider` to enable `ref.watch` in a for-loop. Returns loading while any data is missing.

**SettingsNotifier.propagateDisplayName** — Firestore batch write that updates `displayName` on all `groups/{id}/members` documents where `userId == currentUid`. Called fire-and-forget via `unawaited()` from `setDeviceName`, with a silent `catch (_) {}` per D-15 (no error UI; Firestore offline persistence handles retry).

### Task 2: UI widgets + profile screen (TDD)

**EditNameBottomSheet** — `ConsumerStatefulWidget` with TextEditingController pre-filled with current name. Save flow: spinner (min 600ms) → checkmark → auto-close after 800ms. TextField uses warm input tokens (`inputFillWarm`, `borderWarm`, `focusBorderWarm`).

**ProfileStatsSection** — 3-card `Row` (Groups, Events, Spent) wrapped in a "YOUR JOURNEY" section header. Stat cards show loading dashes while stats load, graceful zeros on error. Spending formatted via `AppFormatters.formatCurrency(amount, 'OMR')` — no hand-rolled format.

**ProfileScreen** — `ConsumerWidget` with identity section (InitialsCircle 64dp + name display or "Set your name" prompt) and stats section. Back button rendered only when `GoRouter.of(context).canPop()`. Entrance animations via `flutter_animate` (fadeIn + slideY). Opens `EditNameBottomSheet` via `showModalBottomSheet` with 28dp top radius.

## Tests

| File | Tests | Coverage |
|------|-------|----------|
| `test/unit/profile_stats_provider_test.dart` | 3 | profileStatsProvider: loading, zero groups, 2-group aggregation |
| `test/unit/settings_notifier_test.dart` | +1 | IDENT-03: propagateDisplayName called silently on setDeviceName |
| `test/features/profile/profile_screen_test.dart` | 8 | IDENT-01 (2), InitialsCircle (1), IDENT-02 (2), STATS-01/02/03 (3) |

**Total: 804 tests passing** (789 pre-existing + 15 new). No regressions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] StreamProvider timing in unit tests**
- **Found during:** Task 1 test run
- **Issue:** `profileStatsProvider` (a `Provider`) reads synchronously, but underlying `StreamProvider` overrides emit asynchronously. Tests called `container.read(profileStatsProvider)` before streams emitted, getting `loading` instead of data.
- **Fix:** Added `await container.read(userGroupsProvider.future)` + `await container.read(groupEventsProvider(...).future)` calls before asserting, then a 10ms delay to allow the computed provider to re-run.
- **Files modified:** `test/unit/profile_stats_provider_test.dart`
- **Commit:** 962b47c

**2. [Rule 1 - Bug] flutter_animate pending timers in widget tests**
- **Found during:** Task 2 test run
- **Issue:** `flutter_animate` creates timers for entrance animation delays (100ms, 200ms). `tester.pump()` without advancing time left pending timers, causing test failures with "A Timer is still pending even after the widget tree was disposed."
- **Fix:** Added `_pumpWithAnimations()` helper that calls `tester.pump()` + `tester.pump(500ms)` + `tester.pump()` to advance past all animation delays.
- **Files modified:** `test/features/profile/profile_screen_test.dart`
- **Commit:** f7472c3

**3. [Rule 2 - Missing] FakeSettingsNotifier complexity removed**
- **Found during:** Task 2 test authoring
- **Issue:** Initial test design had a `FakeSettingsNotifier` class that required synchronous SharedPreferences initialization — not cleanly achievable in Dart.
- **Fix:** Removed `FakeSettingsNotifier` entirely. Tests use `sharedPreferencesProvider.overrideWithValue(prefs)` + `profileStatsProvider.overrideWith(...)` directly, which is the established pattern in the codebase.
- **Files modified:** `test/features/profile/profile_screen_test.dart`
- **Commit:** f7472c3

## Known Stubs

None. All stat values are wired to real providers. The profile screen renders real data from Firestore via existing providers.

## Self-Check: PASSED

All 8 created files exist on disk. Both task commits (962b47c, f7472c3) present in git log. 804 tests passing.
