---
phase: 35-vault-memories
plan: "01"
subsystem: vault, memories
tags: [offline-banner, token-compliance, tdd-green, module-screens]
dependency-graph:
  requires: [35-00]
  provides: [VAULT-OFFLINE, VAULT-TOKENS, MEMORIES-OFFLINE, MEMORIES-TOKENS]
  affects: [vault_screen, memories_screen]
tech-stack:
  added: []
  patterns: [OfflineBanner after ModuleHeader, Column wrap data branch, AppColorTokens gradient]
key-files:
  created: []
  modified:
    - lib/features/vault/screens/vault_screen.dart
    - lib/features/memories/screens/memories_screen.dart
decisions:
  - MemoriesScreen data branch wrapped in Column to enable OfflineBanner above CustomScrollView — same pattern as all prior module screens
  - Pre-existing 3 test failures (add_expense_screen Supabase references) confirmed as not regressions
metrics:
  duration: 3m
  completed: 2026-04-05
  tasks: 3
  files: 2
---

# Phase 35 Plan 01: VaultScreen and MemoriesScreen Token + OfflineBanner Summary

Token-compliant OfflineBanner integration for VaultScreen and MemoriesScreen, replacing hardcoded Color(0xFF...) gradients with AppColorTokens module tokens and turning both Wave 0 failing test stubs GREEN.

## Objective

Three targeted fixes to bring VaultScreen and MemoriesScreen in line with the Phase 28-34 module screen pattern:
1. Replace hardcoded gradients with AppColorTokens tokens (CI compliance)
2. Add OfflineBanner to both screens (pattern consistency)
3. Turn both failing Wave 0 test stubs GREEN

## Tasks Completed

### Task 1: Fix VaultScreen — token gradient + OfflineBanner

- Replaced hardcoded `Color(0xFF8B7355)/Color(0xFFA89372)` gradient in EmptyStateView with `AppColorTokens.light.moduleVault/moduleVaultLight`
- Added `import '../../../shared/widgets/offline_banner.dart'`
- Inserted `const OfflineBanner()` between ModuleHeader and Expanded in the main loaded Scaffold Column
- Fixed pre-existing `EdgeInsets.fromLTRB` const lint (Rule 2 auto-fix)
- No changes to offline branch, not-found branch, or pre-event loading branch

### Task 2: Fix MemoriesScreen — token gradient + OfflineBanner (Column wrap data branch)

- Replaced hardcoded `Color(0xFF9B7A5C)/Color(0xFFB89878)` gradient in EmptyStateView with `AppColorTokens.light.moduleMemories/moduleMemoriesLight`
- Added `import '../../../shared/widgets/offline_banner.dart'`
- Wrapped `data:` branch in `Column` — moved ModuleHeader out of slivers, added `const OfflineBanner()`, wrapped CustomScrollView in `Expanded`
- Added `const OfflineBanner()` to `error:` branch Column between ModuleHeader and Expanded
- Left `loading:` branch (CustomScrollView only) unchanged — no OfflineBanner in loading state
- `_showFullScreen` (Navigator.push, opaque: false) left untouched

### Task 3: Turn tests GREEN — confirm all vault and memories tests pass

Both Wave 0 failing stubs now pass:
- `VaultScreen — OfflineBanner renders in body` PASS
- `MemoriesScreen — OfflineBanner renders in body` PASS

Full suite: 869 pass, 3 pre-existing failures (add_expense_screen.dart Supabase references — not regressions, were failing before Phase 35 started).

## Task Commits

| Task | Description | Commit |
|------|-------------|--------|
| 1 | VaultScreen: OfflineBanner + token gradient | fb1780b |
| 2 | MemoriesScreen: OfflineBanner + Column wrap + token gradient | b3d12e6 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing EdgeInsets.fromLTRB const lint in VaultScreen**
- **Found during:** Task 1 flutter analyze
- **Issue:** `EdgeInsets.fromLTRB` missing `const` modifier at line 198 (pre-existing, not caused by this plan's changes)
- **Fix:** Added `const` to `EdgeInsets.fromLTRB(16, 12, 16, 4)`
- **Files modified:** lib/features/vault/screens/vault_screen.dart
- **Commit:** fb1780b

No other deviations — plan executed as written.

## Verification Results

```
=== Token compliance ===
PASS: token compliant (no Color(0xFF...) in vault/ or memories/)

=== OfflineBanner in both screens ===
lib/features/vault/screens/vault_screen.dart
lib/features/memories/screens/memories_screen.dart

=== Phase 35 tests ===
+2: All tests passed! (vault + memories OfflineBanner tests)

=== Full suite ===
869 pass, 3 pre-existing failures (not regressions)
```

## Known Stubs

None — both screens are fully wired.

## Self-Check: PASSED
