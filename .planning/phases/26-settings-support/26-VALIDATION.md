---
phase: 26
slug: settings-support
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (SDK) + mocktail 1.0.4 |
| **Config file** | flutter_test block in pubspec.yaml |
| **Quick run command** | `flutter test test/features/profile/profile_screen_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/profile/profile_screen_test.dart`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 26-01-01 | 01 | 1 | NOTIF-01 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 26-01-02 | 01 | 1 | NOTIF-02 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 26-01-03 | 01 | 1 | INFO-01 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 26-01-04 | 01 | 1 | INFO-02 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 26-01-05 | 01 | 1 | INFO-03 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |
| 26-01-06 | 01 | 1 | SUPP-01 | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New test groups in `test/features/profile/profile_screen_test.dart` — stubs for NOTIF-01, NOTIF-02, INFO-01, INFO-02, INFO-03, SUPP-01
- [ ] `MockNotificationService` — mocktail mock for `notificationServiceProvider`
- [ ] Override for `appMetadataProvider` returning known version string
- [ ] Override for `notificationStatusProvider` to simulate permissionDenied state

*Existing infrastructure covers test framework and runner — only new test groups needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| OS notification permission dialog appears on toggle ON | NOTIF-02 | OS dialog cannot be triggered in widget tests | Toggle ON on physical device → OS prompt appears |
| mailto opens email client | INFO-02 | External app launch cannot be verified in widget tests | Tap "Send Feedback" on device → email client opens with pre-filled subject |
| openAppSettings deep-links to app notification settings | D-08 | OS settings navigation cannot be verified in widget tests | Deny notification permission → tap disabled tile → device settings opens |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
