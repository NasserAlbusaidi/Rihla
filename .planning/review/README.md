# Full Project Review — 2026-04-14

Source: journal.md entry "Full Project Review: 32,592 Lines Under the Microscope"

**Grade: B-** | Architecture: A- | Financial Math: A | Security: D+ | Error Handling: C-

## Progress: 26 fixed | 3 partial | 1 deferred | 10 open

Last checked: 2026-04-15

## Scoreboard

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1a | fcm_tokens no rules | CRITICAL | FIXED |
| 1b | Storage rules any auth | CRITICAL | PARTIAL — needs Cloud Functions |
| 1c | inviteCodes public | CRITICAL | FIXED |
| 1d | deleteGroup blocked | CRITICAL | FIXED |
| 1e | Subcollection wildcard | CRITICAL | FIXED |
| 2 | Split rounding loses money | CRITICAL | FIXED |
| 3 | Wrong user balance | CRITICAL | FIXED |
| 4 | Silent auth failure | CRITICAL | FIXED |
| 5 | Memory photos broken | CRITICAL | FIXED |
| 6 | Edit expense discards changes | HIGH | FIXED |
| 7 | No double-tap guard | HIGH | FIXED |
| 8 | No "already member" check | HIGH | FIXED |
| 9 | Leave/delete ignores balances | HIGH | FIXED |
| 10 | Fire-and-forget deletes | HIGH | FIXED |
| 11 | Vault dismissible race | HIGH | FIXED |
| 12 | No error handling on expense | HIGH | FIXED |
| 13 | Auto-select tab hijacks | HIGH | FIXED |
| 14 | No amount validation | HIGH | FIXED |
| 15 | God screens (5 files) | MEDIUM | **OPEN** |
| 16 | Provider watch explosion | MEDIUM | **OPEN** |
| 17 | Broken dark theme | MEDIUM | **OPEN** |
| 18 | CacheService god class | MEDIUM | **OPEN** |
| 19 | Stale SQLite cache | MEDIUM | FIXED |
| 20 | Database init hang | MEDIUM | FIXED |
| 21 | Non-atomic group create/join | MEDIUM | PARTIAL — Firestore constraint |
| 22 | copyWith can't clear fields | MEDIUM | DEFERRED — no active callers |
| 23 | Connectivity burns reads | MEDIUM | PARTIAL — auth-gated now |
| 24 | OpenContainer bypasses router | MEDIUM | **OPEN** |
| 25 | Hardcoded OMR | MEDIUM | FIXED |
| 26 | ~750 lines dead code | LOW | FIXED |
| 27 | 50+ debugPrint in prod | LOW | FIXED |
| 28 | 16 swallowed exceptions | LOW | **OPEN** |
| 29 | Accessibility gaps | LOW | **OPEN** |
| 30 | Shadow tokens alloc per access | LOW | FIXED |
| 31 | Spacing tokens unused | LOW | **OPEN** |
| 32 | Hardcoded colors | LOW | **OPEN** |
| 33 | Test coverage gaps | LOW | **OPEN** |
| 34 | App says "Safar" | LOW | FIXED |
| 35 | CLAUDE.md radiusSmall wrong | LOW | FIXED |
| 36 | GoRouter version mismatch | LOW | FIXED |

## Remaining Priority

1. Storage membership rules (#1b) — requires Cloud Functions follow-up
2. **God screens** (#15) — 5 files over 800 lines, refactoring needed
3. **Swallowed exceptions** (#28) — 16 empty catch blocks

## By Category

| File | Score | Notes |
|------|-------|-------|
| [01-security.md](01-security.md) | 4/5 fixed | Storage needs Cloud Functions |
| [02-financial-bugs.md](02-financial-bugs.md) | 7/7 fixed | All resolved |
| [03-group-management.md](03-group-management.md) | 4/5 fixed | Non-atomic is Firestore constraint |
| [04-auth-infrastructure.md](04-auth-infrastructure.md) | 2/4 fixed | Connectivity partial, router open |
| [05-broken-features.md](05-broken-features.md) | 2/2 fixed | All resolved |
| [06-architecture-debt.md](06-architecture-debt.md) | 1/6 fixed | God screens, dark theme, cache class |
| [07-code-quality.md](07-code-quality.md) | 6/11 fixed | debugPrint cleaned, 5 remaining |
| [08-patterns-and-priorities.md](08-patterns-and-priorities.md) | — | Cross-cutting observations |
