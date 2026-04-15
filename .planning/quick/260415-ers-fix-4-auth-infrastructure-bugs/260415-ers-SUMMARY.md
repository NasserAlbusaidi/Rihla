# Quick Task 260415-ers: Fix 4 Auth/Infrastructure Bugs

**Date:** 2026-04-15
**Commit:** 6223691
**Review source:** .planning/review/04-auth-infrastructure.md

## Bugs Fixed

| Bug | Severity | File | Fix |
|-----|----------|------|-----|
| 4 — Silent auth failure | CRITICAL | firebase_config.dart | `rethrow` after logging so callers can handle auth failure |
| 20 — Database init hang | HIGH | local_database.dart | Completer completes with error on init failure, resets for retry; `close()` resets completer |
| 23 — Connectivity burns reads | MEDIUM | connectivity_provider.dart | Timer pauses when backgrounded via `WidgetsBindingObserver`; stale "publicly readable" comment fixed |
| 24 — OpenContainer bypasses GoRouter | MEDIUM | home_screen.dart | Replaced with `context.push('/group/${group.id}')` via GoRouter; removed animations import |

## Files Modified

- `lib/core/config/firebase_config.dart` (+1 line — rethrow)
- `lib/core/services/local_database.dart` (+11 -4 lines — try/catch + completer reset)
- `lib/core/providers/connectivity_provider.dart` (+28 -8 lines — lifecycle observer)
- `lib/features/home/screens/home_screen.dart` (+3 -21 lines — GoRouter nav)
- `test/features/home/home_screen_groups_test.dart` (updated OpenContainer test)
- `test/features/home/home_screen_dashboard_test.dart` (updated OpenContainer test)

## Verification

- `flutter analyze` — 0 issues on all 4 source files
- `flutter test` — 892 passed, 0 failures
