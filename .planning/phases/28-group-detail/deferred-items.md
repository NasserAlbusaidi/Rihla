# Deferred Items — Phase 28

Pre-existing test failures discovered during Plan 02 execution. NOT caused by Phase 28 changes.

## Pre-existing Test Failures (out of scope for Phase 28)

### 1. test/features/ledger_test.dart — Compilation Error
- **Error:** `No named parameter with the name 'event'`
- **Line:** test/features/ledger_test.dart:72
- **Root cause:** Test uses `event:` named param that was removed in a prior refactor
- **Status:** Pre-existing, not caused by Plan 01 or Plan 02 changes
- **Recommendation:** Fix in a dedicated test maintenance task

### 2. test/features/group_settle_up_screen_test.dart — Compilation Error
- **Error:** `No named parameter with the name 'group'`
- **Line:** test/features/group_settle_up_screen_test.dart:110
- **Root cause:** Test uses `group:` named param that was removed in a prior refactor
- **Status:** Pre-existing, not caused by Plan 01 or Plan 02 changes
- **Recommendation:** Fix in a dedicated test maintenance task

### 3. test/features/groups/group_screens_test.dart — Invite Code Section Test
- **Error:** `Expected: exactly one matching candidate / Actual: 0 widgets with key group_invite_code_section`
- **Root cause:** Plan 01 removed the invite code section from GroupDetailScreen (D-05).
  The test `shows invite code section header and code display` was not updated as part of Plan 01 scope.
- **Status:** Pre-existing from Plan 01, not caused by Plan 02 changes
- **Recommendation:** Update or remove this test in the same phase that implements the
  invite code section in GroupSettings (Phase 29)
