---
phase: 1
slug: data-foundation
status: draft
nyquist_compliant: false
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
| *Populated after planning* | | | | | | | |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/money_serializer_test.dart` — stubs for DATA-01 (Decimal precision round-trip)
- [ ] `test/unit/firebase_config_test.dart` — stubs for DATA-02 (Firebase init + anonymous auth)
- [ ] `test_rules/` directory with `package.json` + Jest config — stubs for TST-04 (security rule tests)
- [ ] `test/unit/local_database_v6_test.dart` — stubs for DATA-06 (SQLite schema migration)
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

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
