---
phase: 01-data-foundation
plan: 03
subsystem: infra
tags: [firebase, firestore, security-rules, emulator, jest, nodejs]

# Dependency graph
requires:
  - phase: 01-data-foundation-plan-01
    provides: Firebase packages in pubspec; firebase_options.dart already configured

provides:
  - Firebase Emulator configuration for local development (Firestore 8080, Auth 9099, UI 4000)
  - Firestore security rules with memberIds array membership enforcement on groups
  - JS security rule test suite (22 tests) validating all access patterns
  - Group subcollection access via one get() to parent group document
  - Invite codes public-read pattern for join flow

affects:
  - Phase 02 (groups feature): security rules in place before any group data flows
  - Phase 04 (migration): subcollection rules already defined for expenses, gear, etc.
  - CI/CD: JS rule tests must pass before deploying rules to production (D-15)

# Tech tracking
tech-stack:
  added:
    - "@firebase/rules-unit-testing ^5.0.0 (JS, dev, rule testing)"
    - "firebase-admin ^13.0.0 (JS, dev, test peer)"
    - "jest ^29.0.0 (JS, dev, test runner)"
    - "@jest/globals ^29.0.0 (JS, dev)"
  patterns:
    - "Firestore security rules: memberIds array on group doc, no cross-doc get() for group itself"
    - "Subcollection membership: one get() to parent group document (within 10-get limit)"
    - "Default-deny: wildcard catch-all at top, explicit allows below"
    - "Rule tests: withSecurityRulesDisabled() to seed data, authenticatedContext/unauthenticatedContext for access tests"
    - "JS rule tests live in test_rules/ — separate from Dart tests, separate node project"

key-files:
  created:
    - firebase.json
    - .firebaserc
    - firestore.indexes.json
    - security/firestore.rules
    - test_rules/package.json
    - test_rules/jest.config.js
    - test_rules/firestore.test.js
  modified: []

key-decisions:
  - "memberIds is an array on group document — rules use `in` operator for O(1) membership check (D-14)"
  - "Subcollections use one get() to parent for membership — avoids need for duplicating member data (D-14)"
  - "Default-deny wildcard rule at top of rules file — explicit allow is required for every path"
  - "inviteCodes collection is publicly readable for join flow — authenticated write only"
  - "Group delete blocked unconditionally (allow delete: if false) — groups are persistent"

patterns-established:
  - "Rule seeding: use testEnv.withSecurityRulesDisabled() for all test data setup"
  - "Test organization: describe blocks per access category (group access, creation, subcollection, inviteCodes, default deny)"
  - "firebase.json points to security/firestore.rules — rules live in security/ subdirectory, not project root"

requirements-completed: [DATA-02, DATA-03, TST-04]

# Metrics
duration: 2min
completed: 2026-03-26
---

# Phase 01 Plan 03: Firebase Emulator + Security Rules Summary

**Firestore security rules with memberIds array membership, 22 JS rule tests covering all group access patterns, and Firebase Emulator config for local development**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-25T21:20:50Z
- **Completed:** 2026-03-25T21:22:50Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Firebase Emulator configured at project root (firebase.json) with Firestore on port 8080, Auth on 9099, UI on 4000
- Firestore security rules enforce group membership via memberIds array, block deletes unconditionally, and use one get() for subcollection access
- JS rule test suite with 22 tests covering: unauthenticated deny, non-member deny, member read/update, group create validation (name/memberIds/currency required), delete blocked for member and unauthenticated, subcollection access, invite code public read, default deny for unknown collections

## Task Commits

Each task was committed atomically:

1. **Task 1: Firebase Emulator config and Firestore security rules** - `7b1f6d1` (chore)
2. **Task 2: JS security rule test suite** - `ad575c2` (test)

## Files Created/Modified

- `firebase.json` — Emulator config: Firestore 8080, Auth 9099, UI 4000, rules path reference
- `.firebaserc` — Project alias `rihla-app` (placeholder for emulator-only use)
- `firestore.indexes.json` — Empty indexes placeholder (fieldOverrides included)
- `security/firestore.rules` — Group membership rules via memberIds array, isMember()/isValidGroupCreate() helpers, subcollection protection, inviteCodes public read
- `test_rules/package.json` — Node project with @firebase/rules-unit-testing ^5.0.0, type: module
- `test_rules/jest.config.js` — ESM-compatible jest config (transform: {})
- `test_rules/firestore.test.js` — 22 test cases covering all rule access patterns

## Decisions Made

- Followed plan's `memberIds` array pattern (using `in` operator) for group membership — D-14 aligned
- Kept `security/` subdirectory for rules file (not project root) per firebase.json path reference pattern
- 22 tests instead of the minimum 10 — added coverage for edge cases: empty name, missing currency, unauthenticated delete, non-member update, member write to subcollection, default deny

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

To run the JS rule tests locally, Firebase CLI and Node.js are required:

```bash
# Install Firebase CLI (if not installed)
npm install -g firebase-tools

# Install test dependencies
cd test_rules && npm install

# Run tests with emulator (starts emulator, runs tests, stops emulator)
cd test_rules && npm run test:emulator
```

Tests connect to the Firebase Emulator on `127.0.0.1:8080` (Firestore) and `127.0.0.1:9099` (Auth).

## Next Phase Readiness

- Security rules are complete and tested — Phase 02 group features can write data with confidence
- Emulator is configured — developers can run `firebase emulators:start` and test locally
- No remaining blockers for this plan. The Firebase Emulator blocker in STATE.md is resolved.

---
*Phase: 01-data-foundation*
*Completed: 2026-03-26*

## Self-Check: PASSED

All created files confirmed present on disk. All task commits confirmed in git log.

| Item | Status |
|------|--------|
| firebase.json | FOUND |
| .firebaserc | FOUND |
| firestore.indexes.json | FOUND |
| security/firestore.rules | FOUND |
| test_rules/package.json | FOUND |
| test_rules/jest.config.js | FOUND |
| test_rules/firestore.test.js | FOUND |
| 01-03-SUMMARY.md | FOUND |
| Commit 7b1f6d1 (Task 1) | FOUND |
| Commit ad575c2 (Task 2) | FOUND |
