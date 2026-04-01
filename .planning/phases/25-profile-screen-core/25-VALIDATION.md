---
phase: 25
slug: profile-screen-core
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + mocktail |
| **Config file** | `pubspec.yaml` (dev_dependencies section) |
| **Quick run command** | `flutter test test/unit/profile_stats_provider_test.dart test/features/profile/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/profile_stats_provider_test.dart test/features/profile/ --reporter=compact`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 25-01-01 | 01 | 1 | IDENT-01 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 25-01-02 | 01 | 1 | IDENT-02 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 25-01-03 | 01 | 1 | IDENT-03 | unit | `flutter test test/unit/settings_notifier_test.dart` | ❌ W0 | ⬜ pending |
| 25-02-01 | 02 | 1 | STATS-01 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 25-02-02 | 02 | 1 | STATS-02 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 25-02-03 | 02 | 1 | STATS-03 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/features/profile/profile_screen_test.dart` — stubs for IDENT-01, IDENT-02, STATS-01, STATS-02, STATS-03
- [ ] `test/unit/profile_stats_provider_test.dart` — unit test for profileStatsProvider aggregation logic
- [ ] `lib/features/settings/keys/profile_keys.dart` — semantic test keys for profile screen
- [ ] Extend `test/unit/settings_notifier_test.dart` — add test for propagateDisplayName (mocked Firestore)

*Existing infrastructure covers framework install — flutter_test and mocktail already in dev_dependencies.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Bottom sheet keyboard avoidance | IDENT-02 | Keyboard behavior is device-dependent | Open edit sheet, verify text field not obscured by keyboard on iOS/Android |
| Slide-right page transition | IDENT-01 | Animation timing not reliably testable | Navigate to /profile, verify slide-right transition plays smoothly |
| Offline name save + sync on reconnect | IDENT-03 | Requires airplane mode toggle | Edit name while offline, verify SharedPreferences updates immediately, Firestore updates after reconnect |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
