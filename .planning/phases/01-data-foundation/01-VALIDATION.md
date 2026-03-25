---
phase: 1
slug: data-foundation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-26
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter test + Jest (for Firestore security rules) |
| **Config file** | `pubspec.yaml` (Dart), `test_rules/package.json` (JS rules) |
| **Quick run command** | `flutter test test/unit/` |
| **Full suite command** | `flutter test && cd test_rules && npx jest` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/`
- **After every plan wave:** Run `flutter test && cd test_rules && npx jest`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-T1 | 01-01 | 1 | DATA-06 | dependency resolution | `flutter pub get` | pubspec.yaml | pending |
| 01-01-T2 | 01-01 | 1 | DATA-05, DATA-06 | static analysis | `flutter analyze --no-pub 2>&1 \| head -20` | lib/core/config/firebase_config.dart, lib/main.dart, lib/features/auth/providers/firebase_auth_provider.dart | pending |
| 01-01-T3 | 01-01 | 1 | DATA-05 | integration test | `flutter test test/integration/firebase_auth_test.dart` | test/integration/firebase_auth_test.dart | pending |
| 01-02-T1 | 01-02 | 2 | DATA-01, DATA-04 | unit test (TDD) | `flutter test test/unit/money_serializer_test.dart` | lib/core/services/money_serializer.dart, test/unit/money_serializer_test.dart | pending |
| 01-02-T2 | 01-02 | 2 | DATA-04 | unit test (TDD) | `flutter test test/unit/local_database_migration_test.dart` | lib/core/services/local_database.dart, test/unit/local_database_migration_test.dart | pending |
| 01-02-T3 | 01-02 | 2 | DATA-01, TST-03 | integration test (TDD) | `flutter test test/integration/firebase_money_roundtrip_test.dart` | test/integration/firebase_money_roundtrip_test.dart | pending |
| 01-03-T1 | 01-03 | 2 | DATA-02, DATA-03 | file validation | `cat firebase.json \| python3 -m json.tool > /dev/null && test -f security/firestore.rules && test -f .firebaserc && test -f firestore.indexes.json` | firebase.json, .firebaserc, firestore.indexes.json, security/firestore.rules | pending |
| 01-03-T2 | 01-03 | 2 | TST-04 | file validation + line count | `cat test_rules/package.json \| python3 -m json.tool > /dev/null && test -f test_rules/firestore.test.js && wc -l test_rules/firestore.test.js` | test_rules/package.json, test_rules/jest.config.js, test_rules/firestore.test.js | pending |

*Status: pending -- will be updated during execution*

**Nyquist continuity check:** No 3 consecutive tasks lack an automated verify command. Every task has an `<automated>` verify element. Sampling continuity holds.

---

## Wave 0 Requirements

- [ ] `test/unit/money_serializer_test.dart` — stubs for DATA-01 (Decimal precision round-trip)
- [ ] `test/unit/firebase_config_test.dart` — stubs for DATA-02 (Firebase init + anonymous auth)
- [ ] `test_rules/` directory with `package.json` + Jest config — stubs for TST-04 (security rule tests)
- [ ] `test/unit/local_database_v6_test.dart` — stubs for DATA-06 (SQLite schema migration)
- [ ] `test/integration/firebase_auth_test.dart` — stubs for DATA-05 (Firebase anonymous auth behavior)
- [ ] `fake_cloud_firestore` + `firebase_auth_mocks` added to dev_dependencies

*Existing `flutter test` infrastructure covers unit test execution. JS test infrastructure for security rules is new.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Anonymous sign-in on real device | DATA-03 | Firebase Auth emulator differs from production auth flow | 1. Install on physical device 2. Clear app data 3. Launch app 4. Verify no login screen 5. Check Firebase console for anonymous user |
| Firebase Emulator Suite startup | TST-03 | Emulator availability is environment-dependent | 1. Run `firebase emulators:start` 2. Verify Auth + Firestore emulators online 3. Check ports 9099 (Auth) and 8080 (Firestore) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
